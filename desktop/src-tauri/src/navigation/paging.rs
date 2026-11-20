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

mod rail;
use rail::{RailCompletion, TurnRail};

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
    summary: Option<Arc<ChatRead<ChatSummary>>>,
    cursor: Option<TurnCursor>,
    ticket: Uuid,
    loaded: HashSet<TurnId>,
    pending: Option<JoinHandle<()>>,
    rail: TurnRail,
}

pub(super) struct HistoryCompletion {
    ticket: Uuid,
    result: HistoryResult,
}

enum HistoryResult {
    Older(Result<PageRead, BrowseError>),
    Rail(RailCompletion),
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
        summary: Option<ChatRead<ChatSummary>>,
        page: &Page<HistoryTurn, TurnCursor>,
    ) {
        self.owner = Some(HistoryOwner {
            workspace,
            thread,
            connection: connection.clone(),
            summary: summary.map(Arc::new),
            cursor: page.next_cursor.clone(),
            ticket: Uuid::new_v4(),
            loaded: page
                .data
                .iter()
                .map(|turn| turn.activity.id.clone())
                .collect(),
            pending: None,
            rail: TurnRail::new(&page.data),
        });
    }

    pub(super) fn view(&self) -> Option<OlderHistoryView> {
        self.owner.as_ref().and_then(|owner| {
            owner.cursor.as_ref().map(|_| OlderHistoryView {
                ticket: owner.ticket,
                pending: owner.pending.is_some(),
            })
        })
    }
}

impl Navigation {
    pub(super) fn retire_history_pages(&mut self) {
        self.pages.owner = None;
        self.view.older_history = None;
        self.view.turn_rail = None;
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
        let summary = owner.summary.clone().ok_or(IpcError::StaleSelection)?;
        let cursor = owner.cursor.clone().ok_or(IpcError::StaleSelection)?;
        let ticket = owner.ticket;
        let complete = self.pages.sender.clone();
        owner.pending = Some(tauri::async_runtime::spawn(async move {
            let result = CodexBrowser::new(client)
                .history(&summary, Some(&cursor), RPC_TIMEOUT)
                .await;
            let _ = complete
                .send(Box::new(HistoryCompletion {
                    ticket,
                    result: HistoryResult::Older(result),
                }))
                .await;
        }));
        self.view.older_history = self.pages.view();
        self.publish_navigation();
        Ok(())
    }

    pub(super) fn complete_history_page(&mut self, completion: HistoryCompletion) {
        match completion.result {
            HistoryResult::Older(result) => self.complete_older(completion.ticket, result),
            HistoryResult::Rail(result) => self.complete_rail(completion.ticket, result),
        }
    }

    fn complete_older(&mut self, ticket: Uuid, result: Result<PageRead, BrowseError>) {
        let Some(owner) = self
            .pages
            .owner
            .as_mut()
            .filter(|owner| owner.ticket == ticket)
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
        let page = match result
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
        owner.cursor = page
            .next_cursor
            .clone()
            .filter(|next| Some(next) != owner.cursor.as_ref());
        owner.ticket = Uuid::new_v4();
        owner.rail.include_history(&page.data);
        let turn_order = owner.rail.order();
        self.view.turn_rail = Some(owner.rail.view());
        self.view.older_history = self.pages.view();
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        state.publish();
        state
            .projection
            .merge_history(workspace, self.view.clone(), history, &turn_order);
    }
}
