use std::{collections::HashSet, sync::Arc};

use codex_gui_core::{
    codex::{BrowseError, ChatRead, ChatSummary, CodexBrowser, HistoryTurn, Page, TurnCursor},
    identity::{ConnectionIdentity, ThreadId, TurnId},
    ipc::{IpcError, OlderHistoryRequest, OlderHistoryView, TranscriptView, WorkspaceId},
};
use tauri::async_runtime::JoinHandle;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{Navigation, RPC_TIMEOUT, append_turn};

type PageRead = ChatRead<Page<HistoryTurn, TurnCursor>>;

pub(super) struct HistoryPaging {
    owner: Option<HistoryOwner>,
    sender: mpsc::Sender<Box<HistoryCompletion>>,
    pub(super) completed: mpsc::Receiver<Box<HistoryCompletion>>,
}

struct HistoryOwner {
    workspace: WorkspaceId,
    thread: ThreadId,
    connection: ConnectionIdentity,
    summary: Arc<ChatRead<ChatSummary>>,
    cursor: TurnCursor,
    ticket: Uuid,
    loaded: HashSet<TurnId>,
    pending: Option<JoinHandle<()>>,
}

pub(super) struct HistoryCompletion {
    ticket: Uuid,
    result: Result<PageRead, BrowseError>,
}

impl Default for HistoryPaging {
    fn default() -> Self {
        let (sender, completed) = mpsc::channel(4);
        Self {
            owner: None,
            sender,
            completed,
        }
    }
}

impl Drop for HistoryOwner {
    fn drop(&mut self) {
        if let Some(task) = &self.pending {
            task.abort();
        }
    }
}

impl HistoryPaging {
    pub(super) fn install(
        &mut self,
        workspace: WorkspaceId,
        thread: ThreadId,
        connection: &ConnectionIdentity,
        summary: ChatRead<ChatSummary>,
        page: &Page<HistoryTurn, TurnCursor>,
    ) {
        self.owner = page.next_cursor.clone().map(|cursor| HistoryOwner {
            workspace,
            thread,
            connection: connection.clone(),
            summary: Arc::new(summary),
            cursor,
            ticket: Uuid::new_v4(),
            loaded: page
                .data
                .iter()
                .map(|turn| turn.activity.id.clone())
                .collect(),
            pending: None,
        });
    }

    pub(super) fn view(&self) -> Option<OlderHistoryView> {
        self.owner.as_ref().map(|owner| OlderHistoryView {
            ticket: owner.ticket,
            pending: owner.pending.is_some(),
        })
    }
}

impl Navigation {
    pub(super) fn retire_history_pages(&mut self) {
        self.pages.owner = None;
        self.view.older_history = None;
    }

    pub(super) fn load_older_history(
        &mut self,
        request: OlderHistoryRequest,
    ) -> Result<(), IpcError> {
        self.require(request.workspace_id)?;
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .connection
            .client();
        let owner = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| {
                owner.workspace == request.workspace_id
                    && owner.thread.0 == request.chat_id
                    && owner.ticket == request.ticket
                    && &owner.connection == client.identity()
            })
            .ok_or(IpcError::StaleSelection)?;
        if owner.pending.is_some() {
            return Ok(());
        }
        let summary = owner.summary.clone();
        let cursor = owner.cursor.clone();
        let ticket = owner.ticket;
        let complete = self.pages.sender.clone();
        owner.pending = Some(tauri::async_runtime::spawn(async move {
            let result = CodexBrowser::new(client)
                .history(&summary, Some(&cursor), RPC_TIMEOUT)
                .await;
            let _ = complete
                .send(Box::new(HistoryCompletion { ticket, result }))
                .await;
        }));
        self.view.older_history = self.pages.view();
        self.publish_navigation();
        Ok(())
    }

    pub(super) fn complete_history_page(&mut self, completion: HistoryCompletion) {
        let Some(owner) = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| owner.ticket == completion.ticket)
        else {
            return;
        };
        owner.pending = None;
        let Some(selection) = self.selection.as_ref().filter(|selection| {
            selection.id == owner.workspace && selection.thread.as_ref() == Some(&owner.thread)
        }) else {
            return;
        };
        let Some(client) = self
            .backend
            .as_ref()
            .map(|backend| backend.connection.client())
        else {
            return;
        };
        if &owner.connection != client.identity() || selection.checkout.revalidate().is_err() {
            self.retire_history_pages();
            self.publish_navigation();
            return;
        }
        let page = match completion
            .result
            .as_ref()
            .map_err(|error| error.to_string())
            .and_then(|response| {
                response
                    .for_selection(client.identity(), &owner.thread)
                    .map_err(|error| error.to_string())
            }) {
            Ok(page) => page,
            Err(error) => {
                eprintln!("{error}");
                self.view.older_history = self.pages.view();
                self.publish_navigation();
                return;
            }
        };
        let mut history = TranscriptView::default();
        let mut inactive = Vec::new();
        for turn in page
            .data
            .iter()
            .rev()
            .filter(|turn| owner.loaded.insert(turn.activity.id.clone()))
        {
            append_turn(&mut history, &selection.checkout, turn, &mut inactive);
        }
        let workspace = selection.id;
        if let Some(next) = page
            .next_cursor
            .as_ref()
            .filter(|next| *next != &owner.cursor)
        {
            owner.cursor = next.clone();
            owner.ticket = Uuid::new_v4();
        } else {
            self.pages.owner = None;
        }
        self.view.older_history = self.pages.view();
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        state.publish();
        state
            .projection
            .prepend_history(workspace, self.view.clone(), history);
    }
}
