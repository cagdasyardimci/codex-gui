use codex_gui_core::{
    codex::{ChatRead, ChatSummary, HistoryTurn, Page, TurnCursor},
    ipc::{ChildHistoryAction, ChildHistoryPage, ChildHistoryRequest, ChildHistoryTarget},
};
use tokio::sync::watch;

use super::*;

pub(in crate::navigation) struct ChildState {
    thread: ThreadId,
    selection: Uuid,
    summary: Option<Arc<ChatRead<ChatSummary>>>,
    older: Option<(Uuid, TurnCursor)>,
    pending: Option<Uuid>,
    cancel: watch::Sender<()>,
}

pub(in crate::navigation) struct ChildRead {
    request: ChildHistoryRequest,
    ticket: Uuid,
    client: AppServerClient,
    summary: Option<Arc<ChatRead<ChatSummary>>>,
    cursor: Option<TurnCursor>,
    cancel: watch::Receiver<()>,
}

type ChildResult = Result<
    (
        Arc<ChatRead<ChatSummary>>,
        ChatRead<Page<HistoryTurn, TurnCursor>>,
    ),
    Failure,
>;

pub(in crate::navigation) struct ChildFinished {
    read: ChildRead,
    result: ChildResult,
}

impl NavigationHandle {
    pub(crate) async fn child_history(
        &self,
        request: ChildHistoryRequest,
    ) -> Result<ChildHistoryPage, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::PrepareChildRead(request, reply))
            .await?;
        let read = result.await.map_err(|_| IpcError::ProjectUnavailable)?;
        let mut cancel = read.cancel.clone();
        let result = tokio::select! {
            biased;
            _ = cancel.changed() => return Err(IpcError::StaleSelection),
            result = fetch(&read) => result,
        };
        let (reply, result_view) = oneshot::channel();
        self.request(Action::FinishChildRead(
            Box::new(ChildFinished { read, result }),
            reply,
        ))
        .await?;
        result_view.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

async fn fetch(read: &ChildRead) -> ChildResult {
    let browser = CodexBrowser::new(read.client.clone());
    let thread = ThreadId(read.request.target.agent_id.clone());
    let summary = match &read.summary {
        Some(summary) => summary.clone(),
        None => Arc::new(browser.thread_summary(&thread, RPC_TIMEOUT).await?),
    };
    let page = browser
        .history(&summary, read.cursor.as_ref(), RPC_TIMEOUT)
        .await?;
    Ok((summary, page))
}

impl Inspector {
    pub(in crate::navigation) fn close_child(&mut self) {
        self.child = None;
        self.selected_child = None;
        self.refresh_at = None;
    }
}

impl Navigation {
    pub(in crate::navigation) fn close_child_history(
        &mut self,
        target: ChildHistoryTarget,
    ) -> Result<(), IpcError> {
        self.inspector_scope(&target.scope)?;
        if self.inspector.child.as_ref().is_none_or(|child| {
            child.thread.0 != target.agent_id || child.selection != target.selection
        }) {
            return Err(IpcError::StaleSelection);
        }
        self.inspector.close_child();
        Ok(())
    }

    fn child_owner(&self, request: &ChildHistoryRequest) -> Result<AppServerClient, IpcError> {
        self.inspector_scope(&request.target.scope)?;
        if !self
            .inspector
            .agents
            .iter()
            .any(|agent| agent.id == request.target.agent_id)
        {
            return Err(IpcError::StaleSelection);
        }
        self.backend
            .as_ref()
            .map(|backend| backend.connection.client())
            .ok_or(IpcError::StaleSelection)
    }

    pub(in crate::navigation) fn prepare_child_read(
        &mut self,
        request: ChildHistoryRequest,
    ) -> Result<ChildRead, IpcError> {
        let client = self.child_owner(&request)?;
        if matches!(request.action, ChildHistoryAction::Open) {
            self.inspector.close_child();
            let (cancel, _) = watch::channel(());
            self.inspector.selected_child = Some(request.target.agent_id.clone());
            self.inspector.child = Some(ChildState {
                thread: ThreadId(request.target.agent_id.clone()),
                selection: request.target.selection,
                summary: None,
                older: None,
                pending: None,
                cancel,
            });
        }
        let child = self
            .inspector
            .child
            .as_mut()
            .filter(|child| {
                child.thread.0 == request.target.agent_id
                    && child.selection == request.target.selection
                    && child.pending.is_none()
            })
            .ok_or(IpcError::StaleSelection)?;
        let cursor = match request.action {
            ChildHistoryAction::Earlier(ticket) => Some(
                child
                    .older
                    .as_ref()
                    .filter(|(expected, _)| *expected == ticket)
                    .map(|(_, cursor)| cursor.clone())
                    .ok_or(IpcError::StaleSelection)?,
            ),
            ChildHistoryAction::Open | ChildHistoryAction::Refresh => None,
        };
        let ticket = Uuid::new_v4();
        child.pending = Some(ticket);
        Ok(ChildRead {
            request,
            ticket,
            client,
            cursor,
            summary: child.summary.clone(),
            cancel: child.cancel.subscribe(),
        })
    }

    pub(in crate::navigation) fn finish_child_read(
        &mut self,
        outcome: ChildFinished,
    ) -> Result<ChildHistoryPage, IpcError> {
        let client = self.child_owner(&outcome.read.request)?;
        if client.identity() != outcome.read.client.identity() {
            return Err(IpcError::StaleSelection);
        }
        let child = self
            .inspector
            .child
            .as_mut()
            .filter(|child| {
                child.pending == Some(outcome.read.ticket)
                    && child.thread.0 == outcome.read.request.target.agent_id
                    && child.selection == outcome.read.request.target.selection
            })
            .ok_or(IpcError::StaleSelection)?;
        child.pending = None;
        let (summary, page) = outcome.result.map_err(report)?;
        let page = page
            .for_selection(client.identity(), &child.thread)
            .map_err(|error| report(error.into()))?;
        let checkout = client
            .identity()
            .workspace
            .checkout
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        let mut transcript = TranscriptView::default();
        let mut active = Vec::new();
        for turn in page.data.iter().rev() {
            append_turn(&mut transcript, checkout, turn, &mut active);
        }
        if !matches!(outcome.read.request.action, ChildHistoryAction::Refresh)
            || child.summary.is_none()
        {
            child.older = page
                .next_cursor
                .clone()
                .filter(|cursor| Some(cursor) != outcome.read.cursor.as_ref())
                .map(|cursor| (Uuid::new_v4(), cursor));
        }
        child.summary = Some(summary);
        Ok(ChildHistoryPage {
            rows: transcript.items,
            earlier: child.older.as_ref().map(|(ticket, _)| *ticket),
        })
    }
}
