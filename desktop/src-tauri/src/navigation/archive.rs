use std::collections::{HashMap, HashSet};

use codex_gui_core::{
    codex::{ChatSummary, ThreadActivity, ThreadSummary},
    ipc::{
        ArchiveCatalog, ArchiveScope, ArchiveTarget, ArchivedChat, RestoreArchive, SidebarChatKey,
    },
};
use serde::Deserialize;
use serde_json::json;

use super::{
    sidebar::{open_checkout_probe, sidebar_chat_row},
    *,
};

#[derive(Default)]
pub(super) struct ArchiveState {
    read: Option<Uuid>,
    catalog: Option<(Uuid, ConnectionIdentity)>,
    rows: HashMap<ThreadId, ThreadSummary>,
    receipts: HashMap<ThreadId, (bool, ThreadSummary)>,
}

impl ArchiveState {
    pub(super) fn keep_active(&self, id: &ThreadId) -> bool {
        self.receipts.get(id).is_none_or(|(archived, _)| !archived)
    }

    fn confirm(&mut self, thread: &ThreadSummary, archived: bool) {
        self.read = None;
        self.catalog = None;
        self.receipts
            .insert(thread.id.clone(), (archived, thread.clone()));
        if archived {
            self.rows.insert(thread.id.clone(), thread.clone());
        } else {
            self.rows.remove(&thread.id);
        }
    }

    pub(super) fn remove_deleted(&mut self, thread: &ThreadId) {
        self.read = None;
        self.catalog = None;
        self.rows.remove(thread);
        self.receipts.remove(thread);
    }
}

pub(super) struct ArchiveRead {
    ticket: Uuid,
    scope: ArchiveScope,
    client: AppServerClient,
}

pub(super) struct ArchiveReadResult {
    read: ArchiveRead,
    rows: HashMap<ThreadId, ThreadSummary>,
}

impl NavigationHandle {
    pub(crate) async fn read_archive(
        &self,
        scope: ArchiveScope,
    ) -> Result<ArchiveCatalog, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::StartArchiveRead(scope, reply)).await?;
        let read = result.await.map_err(|_| IpcError::ProjectUnavailable)?;
        let rows = read_archive_rows(&read.client).await?;
        let (reply, result) = oneshot::channel();
        self.request(Action::FinishArchiveRead(
            ArchiveReadResult { read, rows },
            reply,
        ))
        .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

pub(super) async fn read_archive_rows(
    client: &AppServerClient,
) -> Result<HashMap<ThreadId, ThreadSummary>, IpcError> {
    let browser = CodexBrowser::new(client.clone());
    let mut cursors = HashSet::new();
    let mut cursor = None;
    let mut rows = HashMap::new();
    loop {
        let page = browser
            .archived_chats(cursor.as_deref(), RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        for thread in page.data {
            if !thread.id.0.is_empty() {
                rows.entry(thread.id.clone()).or_insert(thread);
            }
        }
        let Some(next) = page.next_cursor else { break };
        if !cursors.insert(next.clone()) {
            return Err(report("Codex repeated an archive cursor".into()));
        }
        cursor = Some(next);
    }
    Ok(rows)
}

impl Navigation {
    pub(super) async fn start_archive_read(
        &mut self,
        scope: ArchiveScope,
    ) -> Result<ArchiveRead, IpcError> {
        self.check_archive_scope(&scope)?;
        let client = self.connect().await.map_err(report)?;
        let ticket = Uuid::new_v4();
        self.archive.read = Some(ticket);
        Ok(ArchiveRead {
            ticket,
            scope,
            client,
        })
    }

    pub(super) fn finish_archive_read(
        &mut self,
        read: ArchiveReadResult,
    ) -> Result<ArchiveCatalog, IpcError> {
        self.check_archive_scope(&read.read.scope)?;
        let owner = read.read.client.identity();
        if self.archive.read != Some(read.read.ticket) || !self.owns_archive_client(owner) {
            return Err(IpcError::StaleSelection);
        }
        self.archive.read = None;
        let mut rows = read.rows;
        rows.retain(|id, _| !self.deleted_chats.contains(id));
        self.archive
            .receipts
            .retain(|id, (archived, _)| rows.contains_key(id) != *archived);
        for (id, (archived, thread)) in &self.archive.receipts {
            if *archived {
                rows.insert(id.clone(), thread.clone());
            } else {
                rows.remove(id);
            }
        }
        let projects: HashMap<_, _> = self
            .view
            .sidebar
            .projects
            .iter()
            .map(|project| (Path::new(&project.path), project.title.as_str()))
            .collect();
        let chats = rows
            .values()
            .map(|thread| {
                let project = projects
                    .get(thread.cwd.as_path())
                    .copied()
                    .or_else(|| thread.cwd.file_name().and_then(|name| name.to_str()))
                    .unwrap_or("Other Chats");
                let path = thread.cwd.to_string_lossy().into_owned();
                let (row, _) = sidebar_chat_row(thread.clone());
                ArchivedChat {
                    id: row.id,
                    title: row.title,
                    preview: row.preview,
                    project: project.to_owned(),
                    path,
                    created_at: thread.created_at,
                    updated_at: thread.updated_at,
                }
            })
            .collect();
        self.archive.rows = rows;
        self.archive.catalog = Some((read.read.ticket, owner.clone()));
        Ok(ArchiveCatalog {
            revision: read.read.ticket,
            chats,
        })
    }

    fn check_archive_scope(&self, scope: &ArchiveScope) -> Result<(), IpcError> {
        if self.quit.is_some()
            || self.selection.as_ref().map(|selection| selection.id) != scope.workspace_id
        {
            return Err(IpcError::StaleSelection);
        }
        if let Some(workspace) = scope.workspace_id {
            self.require(workspace)?;
        }
        Ok(())
    }

    fn owns_archive_client(&self, owner: &ConnectionIdentity) -> bool {
        self.backend
            .as_ref()
            .is_some_and(|backend| backend.connection.client().identity() == owner)
    }

    pub(super) async fn archive_client(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<(AppServerClient, Option<AppServerConnection>), IpcError> {
        if let Some((client, _)) = self
            .runtime_connections()
            .find(|(client, _)| client.identity().workspace.checkout.as_ref() == Some(checkout))
        {
            return Ok((client, None));
        }
        let probe = open_checkout_probe(checkout).await.map_err(report)?;
        Ok((probe.client(), Some(probe)))
    }

    pub(super) fn archived_target(
        &self,
        ticket: Uuid,
        thread: &ThreadId,
    ) -> Result<(AppServerClient, ThreadSummary), IpcError> {
        let (revision, owner) = self
            .archive
            .catalog
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        if *revision != ticket || !self.owns_archive_client(owner) {
            return Err(IpcError::StaleSelection);
        }
        let summary = self
            .archive
            .rows
            .get(thread)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        let client = self
            .backend
            .as_ref()
            .expect("validated archive connection")
            .connection
            .client();
        Ok((client, summary))
    }

    pub(super) async fn archive_chat(&mut self, key: SidebarChatKey) -> Result<(), IpcError> {
        self.archive_chat_from(key, None).await
    }

    pub(super) async fn archive_chat_from(
        &mut self,
        key: SidebarChatKey,
        command: Option<(DraftId, String)>,
    ) -> Result<(), IpcError> {
        self.known_sidebar_chat(&key)?;
        let (_, checkout) = self.resolve_sidebar_project(&key.project_id)?;
        let (client, probe) = self.archive_client(&checkout).await?;
        let result = self
            .archive_one(&client, &checkout, &ThreadId(key.chat_id), command)
            .await;
        close_archive_probe(probe).await;
        result
    }

    pub(super) async fn archive_project(&mut self, id: String) -> Result<(), IpcError> {
        let (_, checkout) = self.resolve_sidebar_project(&id)?;
        let (client, probe) = self.archive_client(&checkout).await?;
        let result = self.archive_project_chats(&client, &checkout).await;
        close_archive_probe(probe).await;
        result
    }

    async fn archive_project_chats(
        &mut self,
        client: &AppServerClient,
        checkout: &CheckoutIdentity,
    ) -> Result<(), IpcError> {
        let browser = CodexBrowser::new(client.clone());
        let mut cursors = HashSet::new();
        let mut seen = HashSet::new();
        let mut cursor = None;
        let mut ids = Vec::new();
        loop {
            let page = browser
                .project_chat_activity(cursor.as_ref(), RPC_TIMEOUT)
                .await
                .map_err(|error| report(error.into()))?;
            for chat in page.data {
                if self.archive.keep_active(&chat.thread.id)
                    && !self.deleted_chats.contains(&chat.thread.id)
                    && seen.insert(chat.thread.id.clone())
                {
                    self.check_idle(checkout, &chat)?;
                    ids.push(chat.thread.id);
                }
            }
            let Some(next) = page.next_cursor else { break };
            if !cursors.insert(next.clone()) {
                return Err(report("Codex repeated a project chat cursor".into()));
            }
            cursor = Some(next);
        }
        for thread in ids {
            self.archive_one(client, checkout, &thread, None).await?;
        }
        Ok(())
    }

    pub(super) fn check_idle(
        &self,
        checkout: &CheckoutIdentity,
        summary: &ChatSummary,
    ) -> Result<(), IpcError> {
        if !matches!(
            summary.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) || self
            .owners
            .thread_in_use(checkout, &summary.thread.id)
            .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    pub(super) async fn idle_thread(
        &self,
        client: &AppServerClient,
        checkout: &CheckoutIdentity,
        id: &ThreadId,
    ) -> Result<ThreadSummary, IpcError> {
        let browser = CodexBrowser::new(client.clone());
        let captured = browser
            .thread_summary(id, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let summary = captured
            .for_selection(client.identity(), id)
            .map_err(|error| report(error.into()))?;
        self.check_idle(checkout, summary)?;
        let turns = browser
            .turn_statuses(&captured, None, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        if turns
            .for_selection(client.identity(), id)
            .map_err(|error| report(error.into()))?
            .data
            .iter()
            .any(|turn| !turn.status.is_finished())
        {
            return Err(IpcError::StaleSelection);
        }
        checkout
            .revalidate()
            .map_err(|_| IpcError::RetiredWorkspace)?;
        self.check_idle(checkout, summary)?;
        Ok(summary.thread.clone())
    }

    async fn archive_one(
        &mut self,
        client: &AppServerClient,
        checkout: &CheckoutIdentity,
        id: &ThreadId,
        command: Option<(DraftId, String)>,
    ) -> Result<(), IpcError> {
        let thread = self.idle_thread(client, checkout, id).await?;
        let response = client
            .request("thread/archive", json!({"threadId": id.0}), RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        if !response.is_object() {
            return Err(IpcError::ProjectUnavailable);
        }
        if let Some((draft, text)) = command
            && let Err(error) = self
                .store
                .replace_editor_text(draft, Some(&text), String::new())
        {
            eprintln!("{error}");
        }
        self.apply_archive(&thread, Some(checkout), true).await
    }

    pub(super) async fn restore_archived(
        &mut self,
        request: RestoreArchive,
    ) -> Result<(), IpcError> {
        let (revision, owner) = self
            .archive
            .catalog
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        if *revision != request.revision || !self.owns_archive_client(owner) {
            return Err(IpcError::StaleSelection);
        }
        let client = self
            .backend
            .as_ref()
            .expect("validated archive connection")
            .connection
            .client();
        let mut targets: Vec<_> = match request.target {
            ArchiveTarget::Chat(id) => self
                .archive
                .rows
                .get(&ThreadId(id))
                .cloned()
                .into_iter()
                .collect(),
            ArchiveTarget::Project(path) => self
                .archive
                .rows
                .values()
                .filter(|thread| thread.cwd == Path::new(&path))
                .cloned()
                .collect(),
        };
        if targets.is_empty() {
            return Err(IpcError::StaleSelection);
        }
        targets.sort_by(|left, right| left.id.0.cmp(&right.id.0));
        for thread in targets {
            self.restore_one(&client, thread).await?;
        }
        Ok(())
    }

    async fn restore_one(
        &mut self,
        client: &AppServerClient,
        previous: ThreadSummary,
    ) -> Result<(), IpcError> {
        #[derive(Deserialize)]
        struct Restored {
            thread: ThreadSummary,
        }
        let checkout = CheckoutIdentity::capture(&previous.cwd).ok();
        if let Some(checkout) = &checkout
            && self
                .owners
                .thread_in_use(checkout, &previous.id)
                .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        let value = client
            .request(
                "thread/unarchive",
                json!({"threadId": previous.id.0}),
                RPC_TIMEOUT,
            )
            .await
            .map_err(|error| report(error.into()))?;
        let restored: Restored =
            serde_json::from_value(value).map_err(|error| report(error.into()))?;
        let thread = restored.thread;
        if thread.id != previous.id {
            return Err(IpcError::StaleSelection);
        }
        if let Some(checkout) = &checkout {
            checkout
                .validate_reported(&thread.cwd)
                .map_err(|_| IpcError::RetiredWorkspace)?;
        } else if thread.cwd != previous.cwd {
            return Err(IpcError::RetiredWorkspace);
        }
        let registered = if let Some(checkout) = &checkout {
            self.store
                .sidebar_project(&checkout.storage_key())
                .map_err(|error| report(error.into()))?
                .is_some()
        } else {
            false
        };
        self.apply_archive(&thread, checkout.as_ref().filter(|_| registered), false)
            .await
    }

    async fn apply_archive(
        &mut self,
        thread: &ThreadSummary,
        checkout: Option<&CheckoutIdentity>,
        archived: bool,
    ) -> Result<(), IpcError> {
        if archived {
            self.titles.cancel_chat(&thread.id);
        }
        self.archive.confirm(thread, archived);
        if let Some(checkout) = checkout {
            let (row, updated_at) = sidebar_chat_row(thread.clone());
            self.store
                .set_sidebar_archived(checkout, &row, updated_at, archived)
                .map_err(|error| report(error.into()))?;
            self.reload_sidebar().map_err(report)?;
            if let Some(selection) = &self.selection
                && &selection.checkout == checkout
            {
                self.view.chats.retain(|item| item.id != row.id);
                if !archived {
                    self.view.chats.insert(0, row);
                } else if selection.thread.as_ref() == Some(&thread.id) {
                    self.focus(None).await.map_err(report)?;
                }
            }
        }
        self.publish_navigation();
        Ok(())
    }
}

pub(super) async fn close_archive_probe(probe: Option<AppServerConnection>) {
    if let Some(probe) = probe
        && let Err(error) = probe.disconnect().await
    {
        eprintln!("{error}");
    }
}
