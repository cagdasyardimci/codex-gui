use codex_gui_core::{
    codex::{ThreadActivity, ThreadSummary},
    ipc::{
        ChatRow, SidebarChange, SidebarChatKey, SidebarGroup, SidebarMove, SidebarProjectRequest,
        SidebarRequest, SidebarSort, present_question_reply,
    },
};
use serde_json::json;

use super::*;

impl NavigationHandle {
    pub(crate) async fn sidebar_project_path(
        &self,
        request: SidebarProjectRequest,
    ) -> Result<PathBuf, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::SidebarProjectPath(request, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl Navigation {
    pub(super) fn remember_sidebar_chat(
        &mut self,
        row: &ChatRow,
        updated_at: i64,
    ) -> Result<(), Failure> {
        let checkout = &self
            .selection
            .as_ref()
            .ok_or("missing selected project")?
            .checkout;
        self.store
            .remember_sidebar_chats(checkout, [(row.clone(), updated_at)])?;
        self.reload_sidebar()
    }

    pub(super) fn reload_sidebar(&mut self) -> Result<(), Failure> {
        let selected = self
            .selection
            .as_ref()
            .map(|selection| selection.checkout.storage_key());
        let mut view = self.store.sidebar_view(selected)?;
        view.revision = self.view.sidebar.revision;
        if view.revision.is_none() || view != self.view.sidebar {
            view.revision = Some(Uuid::new_v4());
        }
        self.view.sidebar = view;
        Ok(())
    }

    pub(super) fn sidebar_path(&self, request: SidebarProjectRequest) -> Result<PathBuf, IpcError> {
        self.check_sidebar_revision(request.revision)?;
        self.resolve_sidebar_project(&request.project_id)
            .map(|(path, _)| path)
    }

    fn check_sidebar_revision(&self, revision: Uuid) -> Result<(), IpcError> {
        if self.view.sidebar.revision != Some(revision) || self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    fn resolve_sidebar_project(&self, id: &str) -> Result<(PathBuf, CheckoutIdentity), IpcError> {
        let project = self
            .store
            .sidebar_project(id)
            .map_err(|error| report(error.into()))?
            .ok_or(IpcError::StaleSelection)?;
        let path = PathBuf::from(project.path);
        let checkout = CheckoutIdentity::capture(&path).map_err(|_| IpcError::RetiredWorkspace)?;
        if checkout.storage_key() != id {
            return Err(IpcError::RetiredWorkspace);
        }
        Ok((path, checkout))
    }

    fn known_sidebar_chat(&self, key: &SidebarChatKey) -> Result<(), IpcError> {
        if !self.view.sidebar.chats.iter().any(|chat| &chat.key == key) {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    pub(super) async fn edit_sidebar(&mut self, request: SidebarRequest) -> Result<(), IpcError> {
        self.check_sidebar_revision(request.revision)?;
        match request.change {
            SidebarChange::OpenProject(project) => {
                let (path, checkout) = self.resolve_sidebar_project(&project)?;
                if self
                    .selection
                    .as_ref()
                    .is_some_and(|current| current.checkout == checkout)
                {
                    return Ok(());
                }
                self.select(path, checkout, None).await.map_err(report)?;
            }
            SidebarChange::OpenChat(key) => self.open_sidebar_chat(key).await?,
            SidebarChange::RenameProject(project) => {
                self.resolve_sidebar_project(&project.project_id)?;
                let title = checked_title(&project.title)?;
                self.store
                    .rename_sidebar_project(&project.project_id, title)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::RenameChat(chat) => {
                self.rename_sidebar_chat(chat.key, &chat.title).await?
            }
            SidebarChange::PinProject(project) => {
                self.resolve_sidebar_project(&project.project_id)?;
                self.store
                    .pin_sidebar_project(&project.project_id, project.pinned)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::PinChat(chat) => {
                self.known_sidebar_chat(&chat.key)?;
                self.resolve_sidebar_project(&chat.key.project_id)?;
                self.store
                    .pin_sidebar_chat(&chat.key, chat.pinned)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::MarkUnread(chat) => {
                self.known_sidebar_chat(&chat.key)?;
                self.resolve_sidebar_project(&chat.key.project_id)?;
                self.store
                    .mark_sidebar_chat(&chat.key, chat.unread)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::Group(group) => {
                let mut preferences = self
                    .store
                    .sidebar_preferences()
                    .map_err(|error| report(error.into()))?;
                preferences.group = group;
                self.store
                    .save_sidebar_preferences(&preferences)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::Sort(sort) => {
                let mut preferences = self
                    .store
                    .sidebar_preferences()
                    .map_err(|error| report(error.into()))?;
                preferences.sort = sort;
                if sort == SidebarSort::Manual && preferences.order.is_empty() {
                    preferences.order = self
                        .view
                        .sidebar
                        .chats
                        .iter()
                        .map(|chat| chat.key.clone())
                        .collect();
                }
                self.store
                    .save_sidebar_preferences(&preferences)
                    .map_err(|error| report(error.into()))?;
            }
            SidebarChange::MoveChat(movement) => self.move_sidebar_chat(movement)?,
        };
        self.reload_sidebar().map_err(report)?;
        self.publish_navigation();
        Ok(())
    }

    async fn open_sidebar_chat(&mut self, key: SidebarChatKey) -> Result<(), IpcError> {
        self.known_sidebar_chat(&key)?;
        let (path, checkout) = self.resolve_sidebar_project(&key.project_id)?;
        let thread = ThreadId(key.chat_id);
        if self
            .selection
            .as_ref()
            .is_some_and(|selection| selection.checkout == checkout)
        {
            if !self.view.chats.iter().any(|chat| chat.id == thread.0) {
                let client = self
                    .backend
                    .as_ref()
                    .ok_or(IpcError::StaleSelection)?
                    .connection
                    .client();
                CodexBrowser::new(client)
                    .thread_summary(&thread, RPC_TIMEOUT)
                    .await
                    .map_err(|error| report(error.into()))?;
            }
            self.focus(Some(thread)).await.map_err(report)?;
        } else {
            validate_cross_project_chat(&checkout, &thread)
                .await
                .map_err(report)?;
            self.select(path, checkout, Some(thread))
                .await
                .map_err(report)?;
        }
        Ok(())
    }

    pub(super) async fn rename_sidebar_chat(
        &mut self,
        key: SidebarChatKey,
        title: &str,
    ) -> Result<(), IpcError> {
        self.known_sidebar_chat(&key)?;
        let title = checked_title(title)?;
        let selection = self
            .selection
            .as_ref()
            .filter(|selection| selection.checkout.storage_key() == key.project_id)
            .ok_or(IpcError::RetiredWorkspace)?;
        self.require(selection.id)?;
        let backend = self.backend.as_ref().ok_or(IpcError::StaleSelection)?;
        let client = backend.connection.client();
        let thread = ThreadId(key.chat_id.clone());
        let browser = CodexBrowser::new(client.clone());
        let summary = browser
            .thread_summary(&thread, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let summary = summary
            .for_selection(client.identity(), &thread)
            .map_err(|error| report(error.into()))?;
        if !matches!(
            summary.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) {
            return Err(IpcError::StaleSelection);
        }
        let _lease = self
            .owners
            .acquire(client.identity())
            .map_err(|error| report(error.into()))?;
        client
            .request(
                "thread/name/set",
                json!({ "threadId": thread.0, "name": title }),
                RPC_TIMEOUT,
            )
            .await
            .map_err(|error| report(error.into()))?;
        self.store
            .rename_sidebar_chat(&key, title)
            .map_err(|error| report(error.into()))?;
        if let Some(row) = self.view.chats.iter_mut().find(|row| row.id == key.chat_id) {
            row.title = title.to_owned();
        }
        self.reload_sidebar().map_err(report)?;
        self.publish_navigation();
        Ok(())
    }

    fn move_sidebar_chat(&mut self, movement: SidebarMove) -> Result<(), IpcError> {
        let SidebarMove {
            source,
            target,
            after,
        } = movement;
        let view = &self.view.sidebar;
        if view.sort != SidebarSort::Manual {
            return Err(IpcError::StaleSelection);
        }
        let moved = view
            .chats
            .iter()
            .find(|chat| chat.key == source)
            .ok_or(IpcError::StaleSelection)?;
        let destination = view
            .chats
            .iter()
            .find(|chat| chat.key == target)
            .ok_or(IpcError::StaleSelection)?;
        if moved.pinned != destination.pinned
            || view.group == SidebarGroup::ByProject
                && !moved.pinned
                && source.project_id != target.project_id
        {
            return Err(IpcError::StaleSelection);
        }
        if source == target {
            return Ok(());
        }
        let mut order: Vec<_> = view
            .chats
            .iter()
            .filter(|chat| chat.key != source)
            .map(|chat| chat.key.clone())
            .collect();
        let at = order
            .iter()
            .position(|key| key == &target)
            .ok_or(IpcError::StaleSelection)?;
        order.insert(at + usize::from(after), source);
        let mut preferences = self
            .store
            .sidebar_preferences()
            .map_err(|error| report(error.into()))?;
        preferences.order = order;
        self.store
            .save_sidebar_preferences(&preferences)
            .map_err(|error| report(error.into()))
    }

    pub(super) fn clear_selected_unread(&mut self) -> Result<(), Failure> {
        if let (Some(selection), Some(chat_id)) =
            (&self.selection, self.view.selected_chat.as_ref())
        {
            let key = SidebarChatKey {
                project_id: selection.checkout.storage_key(),
                chat_id: chat_id.clone(),
            };
            self.store.mark_sidebar_chat(&key, false)?;
        }
        self.reload_sidebar()
    }

    pub(super) fn record_chat_activity(&mut self, thread: &ThreadId) -> Result<(), Failure> {
        if let Some(selection) = self.selection.as_ref() {
            let key = SidebarChatKey {
                project_id: selection.checkout.storage_key(),
                chat_id: thread.0.clone(),
            };
            self.store
                .sidebar_chat_finished(&key, selection.thread.as_ref() != Some(thread))?;
            self.reload_sidebar()?;
            self.publish_navigation();
        }
        Ok(())
    }
}

pub(super) fn sidebar_chat_row(chat: ThreadSummary) -> (ChatRow, i64) {
    let preview = present_question_reply(&chat.preview).into_owned();
    let title = chat
        .name
        .filter(|name| !name.trim().is_empty())
        .or_else(|| {
            preview
                .lines()
                .find(|line| !line.trim().is_empty())
                .map(str::to_owned)
        })
        .unwrap_or_else(|| "New Chat".into());
    (
        ChatRow {
            id: chat.id.0,
            title,
            preview,
        },
        chat.updated_at,
    )
}

pub(super) fn sidebar_timestamp() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|elapsed| i64::try_from(elapsed.as_secs()).ok())
        .unwrap_or_default()
}

fn checked_title(title: &str) -> Result<&str, IpcError> {
    let title = title.trim();
    if title.is_empty() || title.len() > 1024 || title.chars().any(char::is_control) {
        return Err(IpcError::StaleSelection);
    }
    Ok(title)
}

async fn validate_cross_project_chat(
    checkout: &CheckoutIdentity,
    thread: &ThreadId,
) -> Result<(), Failure> {
    let executable = CodexExecutable::discover(None)?;
    let identity = ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::new_v4()),
            checkout: Some(checkout.clone()),
        },
        generation: ConnectionGeneration(1),
    };
    let probe =
        AppServerConnection::connect(&executable, identity, desktop_client_info(), RPC_TIMEOUT)
            .await?;
    let result = CodexBrowser::new(probe.client())
        .thread_summary(thread, RPC_TIMEOUT)
        .await;
    probe.disconnect().await?;
    result?;
    Ok(())
}
