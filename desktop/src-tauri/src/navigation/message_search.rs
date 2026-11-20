use codex_gui_core::{
    codex::{ChatRead, ChatSummary, HistoryTurn, Page, TurnCursor},
    ipc::{MessageSearchHitRequest, MessageSearchPage, MessageSearchPageRequest},
};
use tokio::sync::watch;

use super::*;

pub(super) struct SearchSession {
    id: Uuid,
    workspace: WorkspaceId,
    connection: ConnectionIdentity,
    chats: HashMap<ThreadId, ChatPages>,
    pending: Option<Uuid>,
    cancel: watch::Sender<()>,
}

struct ChatPages {
    summary: Arc<ChatRead<ChatSummary>>,
    cursor: Option<TurnCursor>,
}

type SearchHistory = (
    Arc<ChatRead<ChatSummary>>,
    ChatRead<Page<HistoryTurn, TurnCursor>>,
);

pub(super) struct SearchRead {
    session: Uuid,
    request: Uuid,
    thread: ThreadId,
    client: AppServerClient,
    prior: Option<Arc<ChatRead<ChatSummary>>>,
    cursor: Option<TurnCursor>,
    canceled: watch::Receiver<()>,
}

pub(super) struct FinishedSearchRead {
    read: SearchRead,
    result: Result<SearchHistory, Failure>,
}

impl NavigationHandle {
    pub(crate) async fn open_message_search(
        &self,
        workspace: WorkspaceId,
    ) -> Result<Uuid, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::OpenMessageSearch(workspace, reply))
            .await?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub(crate) async fn read_message_search_page(
        &self,
        page: MessageSearchPageRequest,
    ) -> Result<MessageSearchPage, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::PrepareSearchPage(page, reply)).await?;
        let read = result.await.map_err(|_| IpcError::ProjectUnavailable)?;
        let mut canceled = read.canceled.clone();
        let result = tokio::select! {
            biased;
            _ = canceled.changed() => return Err(IpcError::StaleSelection),
            result = read.fetch() => result,
        };
        let (reply, response) = oneshot::channel();
        self.request(Action::FinishSearchPage(
            Box::new(FinishedSearchRead { read, result }),
            reply,
        ))
        .await?;
        response.await.map_err(|_| IpcError::ProjectUnavailable)
    }
}

impl SearchRead {
    async fn fetch(&self) -> Result<SearchHistory, Failure> {
        let browser = CodexBrowser::new(self.client.clone());
        let summary = match &self.prior {
            Some(summary) => summary.clone(),
            None => Arc::new(browser.thread_summary(&self.thread, RPC_TIMEOUT).await?),
        };
        let page = browser
            .history(&summary, self.cursor.as_ref(), RPC_TIMEOUT)
            .await?;
        Ok((summary, page))
    }
}

impl Navigation {
    pub(super) fn open_message_search(&mut self, workspace: WorkspaceId) -> Result<Uuid, IpcError> {
        self.require(workspace)?;
        if self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let client = self.search_client()?;
        let id = Uuid::new_v4();
        let (cancel, _) = watch::channel(());
        self.message_search = Some(SearchSession {
            id,
            workspace,
            connection: client.identity().clone(),
            pending: None,
            chats: HashMap::new(),
            cancel,
        });
        Ok(id)
    }

    pub(super) fn close_message_search(&mut self, ticket: Uuid) -> Result<(), IpcError> {
        if self
            .message_search
            .as_ref()
            .is_none_or(|search| search.id != ticket)
        {
            return Err(IpcError::StaleSelection);
        }
        self.message_search = None;
        Ok(())
    }

    fn search_client(&self) -> Result<AppServerClient, IpcError> {
        self.backend
            .as_ref()
            .map(|backend| backend.connection.client())
            .ok_or(IpcError::StaleSelection)
    }

    fn search_member(&self, chat: &str) -> Result<(), IpcError> {
        let project = self
            .view
            .sidebar
            .active_project
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        if self.quit.is_some()
            || !self
                .view
                .sidebar
                .chats
                .iter()
                .any(|row| &row.key.project_id == project && row.key.chat_id == chat)
        {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    fn search_workspace(
        &self,
        ticket: Uuid,
        client: &AppServerClient,
    ) -> Result<WorkspaceId, IpcError> {
        let session = self
            .message_search
            .as_ref()
            .filter(|search| search.id == ticket && &search.connection == client.identity())
            .ok_or(IpcError::StaleSelection)?;
        self.require(session.workspace)?;
        Ok(session.workspace)
    }

    pub(super) fn prepare_search_page(
        &mut self,
        page: MessageSearchPageRequest,
    ) -> Result<SearchRead, IpcError> {
        let client = self.search_client()?;
        self.search_workspace(page.session, &client)?;
        self.search_member(&page.chat_id)?;
        let session = self
            .message_search
            .as_mut()
            .expect("validated search session");
        if session.pending.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let thread = ThreadId(page.chat_id);
        let prior = session.chats.get(&thread);
        let cursor = if page.restart {
            None
        } else if let Some(prior) = prior {
            Some(prior.cursor.clone().ok_or(IpcError::StaleSelection)?)
        } else {
            None
        };
        let request = Uuid::new_v4();
        session.pending = Some(request);
        Ok(SearchRead {
            session: page.session,
            request,
            thread,
            client,
            cursor,
            prior: prior.map(|state| state.summary.clone()),
            canceled: session.cancel.subscribe(),
        })
    }

    pub(super) fn finish_search_page(
        &mut self,
        outcome: FinishedSearchRead,
    ) -> Result<MessageSearchPage, IpcError> {
        let client = self.search_client()?;
        self.search_workspace(outcome.read.session, &client)?;
        let session = self
            .message_search
            .as_mut()
            .expect("validated search session");
        if session.pending != Some(outcome.read.request) {
            return Err(IpcError::StaleSelection);
        }
        session.pending = None;
        self.search_member(&outcome.read.thread.0)?;
        let (summary, response) = outcome.result.map_err(report)?;
        let page = response
            .for_selection(client.identity(), &outcome.read.thread)
            .map_err(|error| report(error.into()))?;
        let checkout = client
            .identity()
            .workspace
            .checkout
            .as_ref()
            .ok_or(IpcError::StaleSelection)?;
        let mut view = TranscriptView::default();
        let mut active = Vec::new();
        for turn in page
            .data
            .iter()
            .rev()
            .filter(|turn| turn.activity.status.is_finished())
        {
            append_turn(&mut view, checkout, turn, &mut active);
        }
        let cursor = page
            .next_cursor
            .clone()
            .filter(|next| Some(next) != outcome.read.cursor.as_ref());
        let more = cursor.is_some();
        self.message_search
            .as_mut()
            .expect("validated search session")
            .chats
            .insert(outcome.read.thread, ChatPages { summary, cursor });
        Ok(MessageSearchPage {
            rows: view.items,
            more,
        })
    }

    pub(super) async fn open_message_search_hit(
        &mut self,
        request: MessageSearchHitRequest,
    ) -> Result<(), IpcError> {
        let client = self.search_client()?;
        if self.search_workspace(request.session, &client)? != request.workspace_id {
            return Err(IpcError::StaleSelection);
        }
        self.search_member(&request.chat_id)?;
        self.close_message_search(request.session)?;
        self.focus(Some(ThreadId(request.chat_id)))
            .await
            .map_err(report)?;
        self.jump_to_history_item(request.workspace_id, request.turn_id, Some(request.item_id))
    }
}
