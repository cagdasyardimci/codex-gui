use codex_gui_core::{
    codex::{ChatSummary, RequestError, ThreadActivity, ThreadSummary},
    ipc::{ConfirmDeleteChat, DeleteChatSource, SendRequest, SidebarDeleteSource},
    worktree::{Edition, WorktreeManager, WorktreePhase, WorktreeStore},
};
use serde::Deserialize;
use serde_json::json;

use super::{
    archive::{close_archive_probe, read_archive_rows},
    sidebar::sidebar_chat_row,
    *,
};

pub(super) struct CapturedDeletion {
    ticket: Uuid,
    workspace: Option<WorkspaceId>,
    source: DeleteChatSource,
    slash: Option<SendRequest>,
    archived_checkout: Option<CheckoutIdentity>,
}

impl NavigationHandle {
    pub(crate) async fn prepare_chat_deletion(
        &self,
        source: DeleteChatSource,
    ) -> Result<ConfirmDeleteChat, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::PrepareChatDeletion(source, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(super) fn capture_chat_deletion(
        &mut self,
        source: DeleteChatSource,
        slash: Option<SendRequest>,
    ) -> Result<ConfirmDeleteChat, IpcError> {
        if self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let (title, archived_checkout) = match &source {
            DeleteChatSource::Sidebar(SidebarDeleteSource { revision, key }) => {
                self.check_sidebar_revision(*revision)?;
                self.resolve_sidebar_project(&key.project_id)?;
                let title = self
                    .view
                    .sidebar
                    .chats
                    .iter()
                    .find(|chat| &chat.key == key)
                    .map(|chat| chat.title.clone())
                    .ok_or(IpcError::StaleSelection)?;
                (title, None)
            }
            DeleteChatSource::Archive(request) => {
                let (_, summary) =
                    self.archived_target(request.revision, &ThreadId(request.chat_id.clone()))?;
                let checkout = CheckoutIdentity::capture(&summary.cwd).ok();
                (sidebar_chat_row(summary).0.title, checkout)
            }
        };
        let ticket = Uuid::new_v4();
        self.deletion = Some(CapturedDeletion {
            ticket,
            workspace: self.selection.as_ref().map(|selection| selection.id),
            source,
            slash,
            archived_checkout,
        });
        Ok(ConfirmDeleteChat { ticket, title })
    }

    pub(super) fn cancel_chat_deletion(&mut self, ticket: Uuid) -> Result<(), IpcError> {
        self.take_chat_deletion(ticket).map(|_| ())
    }

    fn take_chat_deletion(&mut self, ticket: Uuid) -> Result<CapturedDeletion, IpcError> {
        if self
            .deletion
            .as_ref()
            .is_none_or(|captured| captured.ticket != ticket)
        {
            return Err(IpcError::StaleSelection);
        }
        self.deletion.take().ok_or(IpcError::StaleSelection)
    }

    pub(super) async fn confirm_chat_deletion(&mut self, ticket: Uuid) -> Result<(), IpcError> {
        let captured = self.take_chat_deletion(ticket)?;
        if captured.workspace != self.selection.as_ref().map(|selection| selection.id) {
            return Err(IpcError::StaleSelection);
        }
        if let Some(slash) = &captured.slash
            && (self.view.selected_chat != slash.chat_id
                || self
                    .view
                    .draft
                    .as_ref()
                    .is_none_or(|draft| draft.id != slash.draft_id || draft.text != slash.text))
        {
            return Err(IpcError::StaleSelection);
        }
        match captured.source {
            DeleteChatSource::Sidebar(request) => {
                self.check_sidebar_revision(request.revision)?;
                self.known_sidebar_chat(&request.key)?;
                let (_, checkout) = self.resolve_sidebar_project(&request.key.project_id)?;
                let thread = ThreadId(request.key.chat_id);
                let (client, probe) = self.archive_client(&checkout).await?;
                let result = self.delete_active_chat(&client, &checkout, &thread).await;
                close_archive_probe(probe).await;
                result?;
                self.remove_deleted_checkout(&checkout, &thread).await;
            }
            DeleteChatSource::Archive(request) => {
                let thread = ThreadId(request.chat_id);
                let (client, summary) = self.archived_target(request.revision, &thread)?;
                let checkout = captured.archived_checkout.as_ref();
                self.delete_archived_chat(&client, &summary, checkout)
                    .await?;
                if let Some(checkout) = checkout {
                    self.remove_deleted_checkout(checkout, &thread).await;
                }
            }
        }
        Ok(())
    }

    async fn delete_active_chat(
        &mut self,
        client: &AppServerClient,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<(), IpcError> {
        let browser = CodexBrowser::new(client.clone());
        let mut cursor = None;
        let mut seen = HashSet::new();
        loop {
            let page = browser
                .project_chats(false, cursor.as_ref(), RPC_TIMEOUT)
                .await
                .map_err(|error| report(error.into()))?;
            if page.data.iter().any(|chat| &chat.id == thread) {
                break;
            }
            let next = page.next_cursor.ok_or(IpcError::StaleSelection)?;
            if !seen.insert(next.clone()) {
                return Err(IpcError::StaleSelection);
            }
            cursor = Some(next);
        }
        self.idle_thread(client, checkout, thread).await?;
        self.delete_chat(client, thread).await
    }

    async fn delete_archived_chat(
        &mut self,
        client: &AppServerClient,
        summary: &ThreadSummary,
        checkout: Option<&CheckoutIdentity>,
    ) -> Result<(), IpcError> {
        #[derive(Deserialize)]
        struct Read {
            thread: ChatSummary,
        }
        let rows = read_archive_rows(client).await?;
        let current = rows.get(&summary.id).ok_or(IpcError::StaleSelection)?;
        if current.cwd != summary.cwd {
            return Err(IpcError::StaleSelection);
        }
        let response = client
            .request(
                "thread/read",
                json!({"threadId": summary.id.0, "includeTurns": false}),
                RPC_TIMEOUT,
            )
            .await
            .map_err(|error| report(error.into()))?;
        let activity: Read =
            serde_json::from_value(response).map_err(|error| report(error.into()))?;
        if activity.thread.thread.id != summary.id || activity.thread.thread.cwd != summary.cwd {
            return Err(IpcError::StaleSelection);
        }
        if let Some(checkout) = checkout {
            checkout
                .validate_reported(&summary.cwd)
                .map_err(|_| IpcError::RetiredWorkspace)?;
            self.check_idle(checkout, &activity.thread)?;
        } else if !matches!(
            activity.thread.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) {
            return Err(IpcError::StaleSelection);
        }
        self.delete_chat(client, &summary.id).await
    }

    async fn delete_chat(
        &mut self,
        client: &AppServerClient,
        thread: &ThreadId,
    ) -> Result<(), IpcError> {
        if !self
            .store
            .prepare_chat_deletion(thread)
            .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        self.titles.cancel_chat(thread);
        match client
            .request("thread/delete", json!({"threadId": thread.0}), RPC_TIMEOUT)
            .await
        {
            Ok(response) if response.is_object() => {}
            Ok(_) => return Err(IpcError::ProjectUnavailable),
            Err(error) => {
                if error.is_unsent() || matches!(error, RequestError::Remote(_)) {
                    self.store
                        .release_chat_deletion(thread)
                        .map_err(|error| report(error.into()))?;
                }
                return Err(report(error.into()));
            }
        }
        if self.view.selected_chat.as_deref() == Some(thread.0.as_str())
            && let Some(draft) = self.view.draft.as_ref()
            && let Ok(id) = Uuid::parse_str(&draft.id)
        {
            self.editable.remove(&DraftId(id));
            self.failed_drafts.remove(&DraftId(id));
        }
        let recorded = self
            .store
            .confirm_chat_deletion(thread)
            .map_err(|error| report(error.into()));
        self.deleted_chats.insert(thread.clone());
        self.archive.remove_deleted(thread);
        self.view.chats.retain(|row| row.id != thread.0);
        self.reload_sidebar().map_err(report)?;
        if self.view.selected_chat.as_deref() == Some(thread.0.as_str()) {
            self.focus(None).await.map_err(report)?;
        }
        self.publish_navigation();
        if recorded.is_ok()
            && let Err(error) = self.store.collect()
        {
            eprintln!("{error}");
        }
        recorded
    }

    async fn remove_deleted_checkout(&mut self, checkout: &CheckoutIdentity, thread: &ThreadId) {
        if let Err(error) = self.try_remove_deleted_checkout(checkout, thread).await {
            eprintln!("{error}");
        }
    }

    async fn try_remove_deleted_checkout(
        &mut self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<(), Failure> {
        if self.file_tools.has_edits(Some(checkout)) {
            return Ok(());
        }
        let store = WorktreeStore::open(&self.worktree_records)?;
        let snapshot = store.snapshot()?;
        if snapshot.authority != Edition::Tauri {
            return Ok(());
        }
        let Some(record) = snapshot.records.into_iter().find(|record| {
            record.phase == WorktreePhase::Active
                && record.thread_id.as_deref() == Some(thread.0.as_str())
                && record.checkout_path == checkout.canonical_path()
        }) else {
            return Ok(());
        };
        let root = CheckoutIdentity::capture(
            record
                .checkout_path
                .parent()
                .ok_or("invalid managed checkout path")?,
        )?;
        let reservation = self.owners.reserve_cleanup(checkout)?;
        let selected = self
            .selection
            .as_ref()
            .is_some_and(|selection| &selection.checkout == checkout);
        if selected {
            self.disconnect().await;
        }
        let result = WorktreeManager::new(store, root)
            .remove_clean(record.id, reservation)
            .await;
        if result.is_ok() {
            self.store.remove_sidebar_project(&checkout.storage_key())?;
            if selected {
                self.clear().await?;
            } else {
                self.reload_sidebar()?;
                self.publish_navigation();
            }
        } else if selected {
            self.refresh().await?;
        }
        result.map(|_| ()).map_err(Into::into)
    }
}
