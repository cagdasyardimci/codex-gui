use std::{
    collections::HashSet,
    error::Error,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{
        AppServerClient, AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable,
        HistoryTurn, LoginCompletion, ServerEvent, TurnStatus,
    },
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    ipc::{
        ChatRow, DraftEdit, EditorDraft, IpcError, NavigationIntent, NavigationView, StreamChange,
        TextBatcher, TranscriptItem, TranscriptRole, TranscriptView, WorkspaceId, WorkspaceRequest,
    },
    storage::{
        attachments::{AttachmentStore, navigation::DesktopSelection},
        drafts::DraftId,
    },
    workspace::{PrepareThread, ResumedMode, RoutedEvent, WorkspaceEngine},
};
use serde_json::Value;
use tokio::{
    sync::{mpsc, oneshot},
    time::MissedTickBehavior,
};
use uuid::Uuid;

use crate::project_ipc::ProjectState;

mod account;
use account::AccountFlow;

const RPC_TIMEOUT: Duration = Duration::from_secs(10);
type Failure = Box<dyn Error + Send + Sync>;
type Outcome = Result<Option<WorkspaceId>, IpcError>;

pub struct NavigationHandle(mpsc::Sender<Message>);

struct Message {
    action: Action,
    reply: oneshot::Sender<Outcome>,
}

enum Action {
    SelectFolder(PathBuf),
    Intent(NavigationIntent),
}

enum Input {
    Command(Option<Message>),
    Backend(Option<ServerEvent>),
    Flush,
}

struct Selection {
    id: WorkspaceId,
    session: CheckoutSessionId,
    generation: u64,
    checkout: CheckoutIdentity,
    folder: PathBuf,
    thread: Option<ThreadId>,
}

struct Backend {
    connection: AppServerConnection,
    engine: WorkspaceEngine,
    _effects: mpsc::Receiver<PrepareThread>,
}

struct Navigation {
    store: AttachmentStore,
    source_draft: DraftId,
    model: Arc<Mutex<ProjectState>>,
    selection: Option<Selection>,
    backend: Option<Backend>,
    source_session: CheckoutSessionId,
    source_generation: u64,
    login: AccountFlow,
    view: NavigationView,
    editable: HashSet<DraftId>,
    stream: TextBatcher,
    // Active messages already loaded from history have no delta offset. Use their
    // next complete item as authority so a resumed prefix is never duplicated.
    restored_active_items: Vec<String>,
}

impl NavigationHandle {
    pub fn start(
        database: &Path,
        model: Arc<Mutex<ProjectState>>,
        fixture_project: Option<PathBuf>,
        fixture_account: bool,
    ) -> Result<Self, Failure> {
        let store = AttachmentStore::open(database)?;
        let saved = store.desktop_selection()?;
        let (sender, receiver) = mpsc::channel(32);
        let navigation = Navigation {
            store,
            source_draft: saved.source_draft,
            model,
            selection: None,
            backend: None,
            source_session: CheckoutSessionId(Uuid::new_v4()),
            source_generation: 0,
            login: AccountFlow::new(fixture_account),
            view: NavigationView::default(),
            editable: HashSet::new(),
            stream: TextBatcher::default(),
            restored_active_items: Vec::new(),
        };
        tauri::async_runtime::spawn(navigation.run(saved, fixture_project, receiver));
        Ok(Self(sender))
    }

    pub async fn select(&self, folder: PathBuf) -> Outcome {
        self.request(Action::SelectFolder(folder)).await
    }

    pub async fn apply(&self, intent: NavigationIntent) -> Result<(), IpcError> {
        self.request(Action::Intent(intent)).await.map(|_| ())
    }

    async fn request(&self, action: Action) -> Outcome {
        let (reply, result) = oneshot::channel();
        self.0
            .send(Message { action, reply })
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?;
        result.await.map_err(|_| IpcError::ProjectUnavailable)?
    }
}

impl Navigation {
    async fn run(
        mut self,
        saved: DesktopSelection,
        fixture_project: Option<PathBuf>,
        mut commands: mpsc::Receiver<Message>,
    ) {
        if let Err(error) = self.restore(saved, fixture_project).await {
            eprintln!("{error}");
        }
        let mut timer = tokio::time::interval(Duration::from_millis(20));
        timer.set_missed_tick_behavior(MissedTickBehavior::Skip);
        loop {
            let input = if let Some(backend) = &mut self.backend {
                tokio::select! {
                    biased;
                    _ = timer.tick() => Input::Flush,
                    request = commands.recv() => Input::Command(request),
                    event = backend.connection.next_event() => Input::Backend(event),
                }
            } else {
                Input::Command(commands.recv().await)
            };
            match input {
                Input::Command(Some(message)) => {
                    let result = self.handle(message.action).await;
                    let _ = message.reply.send(result);
                }
                Input::Command(None) => break,
                Input::Backend(Some(event)) => {
                    if let Err(error) = self.handle_backend(event).await {
                        eprintln!("{error}");
                    }
                }
                Input::Backend(None) => {
                    self.flush_stream();
                    self.disconnect().await;
                }
                Input::Flush => self.flush_stream(),
            }
        }
        self.disconnect().await;
    }

    async fn restore(
        &mut self,
        saved: DesktopSelection,
        fixture_project: Option<PathBuf>,
    ) -> Result<(), Failure> {
        self.set_editor(self.source_draft)?;
        self.publish_history(TranscriptView::default());
        if let Some(project) = saved.project
            && let Some(checkout) = project.restore()
        {
            self.select(project.path().to_path_buf(), checkout, saved.thread)
                .await?;
        } else if let Some(path) = fixture_project {
            let checkout = CheckoutIdentity::capture(&path)?;
            self.select(path, checkout, None).await?;
        } else {
            self.refresh().await?;
        }
        Ok(())
    }

    async fn handle(&mut self, action: Action) -> Outcome {
        let action = match action {
            Action::SelectFolder(folder) => {
                let checkout =
                    CheckoutIdentity::capture(&folder).map_err(|_| IpcError::InvalidCheckout)?;
                return self
                    .select(folder, checkout, None)
                    .await
                    .map(Some)
                    .map_err(report);
            }
            Action::Intent(action) => action,
        };
        match action {
            NavigationIntent::EditDraft(edit) => self.edit(edit)?,
            NavigationIntent::OpenChat(request) => {
                self.require(request.workspace_id)?;
                if !self.view.chats.iter().any(|row| row.id == request.chat_id) {
                    return Err(IpcError::StaleSelection);
                }
                self.focus(Some(ThreadId(request.chat_id)))
                    .await
                    .map_err(report)?;
            }
            NavigationIntent::NewChat(request) => {
                self.require_request(request)?;
                self.focus(None).await.map_err(report)?;
            }
            NavigationIntent::ClearProject(request) => {
                self.require_request(request)?;
                self.clear().await.map_err(report)?;
            }
            NavigationIntent::Refresh(request) => {
                self.require_request(request)?;
                self.refresh().await.map_err(report)?;
            }
            NavigationIntent::Reconnect(request) => {
                self.require_request(request)?;
                self.disconnect().await;
                self.refresh().await.map_err(report)?;
            }
            NavigationIntent::Retry(request) => {
                self.require(request.workspace_id)?;
                if !self.view.retryable
                    || self.view.selected_chat.as_ref() != Some(&request.chat_id)
                {
                    return Err(IpcError::StaleSelection);
                }
                self.open_history(true).await.map_err(report)?;
            }
            NavigationIntent::SignIn(scope) => {
                if self.selection.as_ref().map(|selected| selected.id) != scope.workspace_id {
                    return Err(IpcError::StaleSelection);
                }
                if let Some(workspace) = scope.workspace_id {
                    self.require(workspace)?;
                }
                let client = self.connect().await.map_err(report)?;
                let ticket = self.login.start(&client).await.map_err(report)?;
                self.view.account.login_ticket = Some(ticket.to_owned());
                self.publish_navigation();
            }
            NavigationIntent::CancelSignIn(request) => {
                let client = self
                    .backend
                    .as_ref()
                    .ok_or(IpcError::StaleSelection)?
                    .connection
                    .client();
                if !self.login.can_cancel(&client, &request.ticket) {
                    return Err(IpcError::StaleSelection);
                }
                let result = self.login.retire(&client).await;
                self.view.account.login_ticket = None;
                self.publish_navigation();
                result.map_err(report)?;
            }
        }
        Ok(None)
    }

    fn require_request(&self, request: WorkspaceRequest) -> Result<(), IpcError> {
        self.require(request.workspace_id)
    }

    fn require(&self, id: WorkspaceId) -> Result<(), IpcError> {
        let selected = self
            .selection
            .as_ref()
            .filter(|selection| selection.id == id)
            .ok_or(IpcError::RetiredWorkspace)?;
        selected
            .checkout
            .revalidate()
            .map_err(|_| IpcError::RetiredWorkspace)
    }

    async fn select(
        &mut self,
        folder: PathBuf,
        checkout: CheckoutIdentity,
        thread: Option<ThreadId>,
    ) -> Result<WorkspaceId, Failure> {
        self.store
            .save_desktop_selection(Some((&folder, &checkout)), thread.as_ref())?;
        self.disconnect().await;
        let id = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .select_checkout(&folder, checkout.clone());
        self.selection = Some(Selection {
            id,
            session: CheckoutSessionId(Uuid::new_v4()),
            generation: 0,
            checkout,
            folder,
            thread: None,
        });
        self.view = NavigationView::default();
        self.adopt_focus(thread)?;
        if let Err(error) = self.refresh().await {
            eprintln!("{error}");
        }
        Ok(id)
    }

    async fn clear(&mut self) -> Result<(), Failure> {
        self.store.save_desktop_selection(None, None)?;
        self.disconnect().await;
        self.selection = None;
        self.model
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .clear();
        self.view = NavigationView::default();
        self.adopt_focus(None)?;
        self.refresh().await
    }

    async fn focus(&mut self, thread: Option<ThreadId>) -> Result<(), Failure> {
        let selected = self.selection.as_ref().ok_or("missing project selection")?;
        if selected.thread == thread {
            return Ok(());
        }
        self.store.save_desktop_selection(
            Some((&selected.folder, &selected.checkout)),
            thread.as_ref(),
        )?;
        self.adopt_focus(thread)?;
        self.open_history(true).await
    }

    fn adopt_focus(&mut self, thread: Option<ThreadId>) -> Result<(), Failure> {
        let draft = match &thread {
            Some(thread) => self.store.editable_thread_draft(thread)?,
            None => self.source_draft,
        };
        self.set_editor(draft)?;
        self.view.selected_chat = thread.as_ref().map(|thread| thread.0.clone());
        self.view.retryable = false;
        if let Some(selected) = &mut self.selection {
            selected.thread = thread;
        }
        self.stream = TextBatcher::default();
        self.restored_active_items.clear();
        self.publish_history(TranscriptView::default());
        Ok(())
    }

    fn set_editor(&mut self, draft: DraftId) -> Result<(), Failure> {
        let text = self.store.read_editor_draft(draft)?.text;
        self.editable.insert(draft);
        self.view.draft = Some(EditorDraft {
            id: draft.0.to_string(),
            text,
        });
        Ok(())
    }

    fn edit(&mut self, edit: DraftEdit) -> Result<(), IpcError> {
        let id = DraftId(Uuid::parse_str(&edit.draft_id).map_err(|_| IpcError::StaleSelection)?);
        if !self.editable.contains(&id) {
            return Err(IpcError::StaleSelection);
        }
        self.store
            .save_editor_text(id, edit.text.clone())
            .map_err(|error| report(error.into()))?;
        if let Some(draft) = self
            .view
            .draft
            .as_mut()
            .filter(|draft| draft.id == edit.draft_id)
        {
            draft.text = edit.text;
            self.publish_navigation();
        }
        Ok(())
    }

    async fn disconnect(&mut self) {
        if let Some(backend) = self.backend.take() {
            if let Err(error) = self.login.retire(&backend.connection.client()).await {
                eprintln!("{error}");
            }
            if self.view.account.login_ticket.take().is_some() {
                self.publish_navigation();
            }
            if let Err(error) = backend.connection.disconnect().await {
                eprintln!("{error}");
            }
        }
    }

    async fn connect(&mut self) -> Result<AppServerClient, Failure> {
        if self.backend.is_none() {
            let executable = CodexExecutable::discover(None)?;
            let (workspace, generation) = match self.selection.as_mut() {
                Some(selected) => (
                    WorkspaceIdentity {
                        session: selected.session,
                        checkout: Some(selected.checkout.clone()),
                    },
                    &mut selected.generation,
                ),
                None => (
                    WorkspaceIdentity {
                        session: self.source_session,
                        checkout: None,
                    },
                    &mut self.source_generation,
                ),
            };
            *generation = generation
                .checked_add(1)
                .ok_or("connection generation exhausted")?;
            let identity = ConnectionIdentity {
                workspace,
                generation: ConnectionGeneration(*generation),
            };
            let connection = AppServerConnection::connect(
                &executable,
                identity.clone(),
                ClientInfo {
                    name: "codex_gui",
                    title: "Codex GUI",
                    version: env!("CARGO_PKG_VERSION"),
                },
                RPC_TIMEOUT,
            )
            .await?;
            let (engine, effects) = WorkspaceEngine::start(identity);
            self.backend = Some(Backend {
                connection,
                engine,
                _effects: effects,
            });
        }
        let backend = self.backend.as_ref().expect("backend connected");
        Ok(backend.connection.client())
    }

    async fn refresh_account(&mut self, client: AppServerClient) -> Result<(), Failure> {
        let mut account = account::read_account(client).await?;
        account
            .login_ticket
            .clone_from(&self.view.account.login_ticket);
        self.view.account = account;
        self.publish_navigation();
        Ok(())
    }

    async fn refresh(&mut self) -> Result<(), Failure> {
        let client = self.connect().await?;
        if let Err(error) = self.refresh_account(client.clone()).await {
            eprintln!("{error}");
        }
        if self.selection.is_none() {
            return Ok(());
        }
        let browser = CodexBrowser::new(client);
        let chats = browser.project_chats(false, None, RPC_TIMEOUT).await?;
        self.view.chats = chats
            .data
            .into_iter()
            .map(|chat| {
                let title = chat
                    .name
                    .filter(|name| !name.trim().is_empty())
                    .or_else(|| {
                        chat.preview
                            .lines()
                            .find(|line| !line.trim().is_empty())
                            .map(str::to_owned)
                    })
                    .unwrap_or_else(|| "New Chat".into());
                ChatRow {
                    id: chat.id.0,
                    title,
                }
            })
            .collect();
        self.publish_navigation();
        self.open_history(false).await
    }

    async fn open_history(&mut self, acquire_writer: bool) -> Result<(), Failure> {
        let Some(thread) = self
            .selection
            .as_ref()
            .and_then(|selection| selection.thread.clone())
        else {
            return Ok(());
        };
        let client = self
            .backend
            .as_ref()
            .ok_or("Codex is disconnected")?
            .connection
            .client();
        let browser = CodexBrowser::new(client.clone());
        // Read closed turns before requesting writer ownership. Early resume
        // deltas can then follow the visibly restored history.
        let summary = browser.thread_summary(&thread, RPC_TIMEOUT).await?;
        let history = browser.history(&summary, None, RPC_TIMEOUT).await?;
        let page = history.for_selection(client.identity(), &thread)?;
        let mut active = Vec::new();
        let mut before_resume = TranscriptView::default();
        for turn in page.data.iter().rev() {
            before_resume.items.extend(read_turn(turn, &mut active));
        }
        self.stream = TextBatcher::default();
        self.restored_active_items = active;
        self.publish_history(before_resume);

        let backend = self.backend.as_mut().expect("backend connected");
        if (acquire_writer || !self.view.retryable)
            && !backend.engine.snapshot().writable_threads.contains(&thread)
        {
            let resumed = backend
                .engine
                .resume_thread(&mut backend.connection, &self.store, &thread, RPC_TIMEOUT)
                .await?;
            self.view.retryable = matches!(resumed.mode, ResumedMode::ReadOnly);
            self.publish_navigation();
            for event in resumed.events {
                self.present_event(event);
            }
        }
        Ok(())
    }

    async fn handle_backend(&mut self, event: ServerEvent) -> Result<(), Failure> {
        let Some(backend) = &self.backend else {
            return Ok(());
        };
        let client = backend.connection.client();
        if let ServerEvent::Notification { method, params } = &event
            && method == "account/login/completed"
        {
            let notification: LoginCompletion = serde_json::from_value(params.clone())?;
            if let Some(success) = self.login.complete(client.identity(), &notification) {
                self.view.account.login_ticket = None;
                if success {
                    if let Err(error) = self.refresh_account(client).await {
                        self.publish_navigation();
                        return Err(error);
                    }
                } else {
                    self.publish_navigation();
                }
            }
            return Ok(());
        }
        if let Some(event) = backend
            .engine
            .route_session_event(&client, &self.store, event, RPC_TIMEOUT)
            .await?
        {
            self.present_event(event);
        }
        Ok(())
    }

    fn present_event(&mut self, event: RoutedEvent) {
        let RoutedEvent::Conversation {
            thread,
            event: ServerEvent::Notification { method, params },
        } = event
        else {
            return;
        };
        let Some(selection) = self
            .selection
            .as_ref()
            .filter(|selection| selection.thread.as_ref() == Some(&thread))
        else {
            return;
        };
        let Some(turn_id) = params["turnId"].as_str() else {
            if method == "turn/completed" {
                self.flush_stream();
            }
            return;
        };
        let workspace = selection.id;
        match method.as_str() {
            "item/agentMessage/delta" => {
                if let (Some(item), Some(text)) =
                    (params["itemId"].as_str(), params["delta"].as_str())
                {
                    let id = transcript_id(turn_id, item);
                    if !self.restored_active_items.contains(&id)
                        && let Some(change) = self.stream.append(id, text.to_owned())
                    {
                        self.publish_stream(workspace, change);
                    }
                }
            }
            "item/completed" => {
                if let Some(item) = read_item(turn_id, &params["item"], true) {
                    self.restored_active_items.retain(|id| *id != item.item_id);
                    self.flush_stream();
                    self.publish_stream(workspace, StreamChange::FinalItem(item));
                }
            }
            "turn/completed" => self.flush_stream(),
            _ => {}
        }
    }

    fn flush_stream(&mut self) {
        if let (Some(selection), Some(change)) = (&self.selection, self.stream.flush()) {
            self.publish_stream(selection.id, change);
        }
    }

    fn publish_stream(&self, workspace: WorkspaceId, change: StreamChange) {
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        state.publish();
        state.projection.publish_stream(workspace, change);
    }

    fn publish_navigation(&self) {
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        let workspace = state.grants.current_view();
        if self.selection.is_some() && workspace.is_none() {
            state.projection.publish(None);
        } else {
            state.projection.update_navigation(self.view.clone());
        }
    }

    fn publish_history(&self, transcript: TranscriptView) {
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        let workspace = state.grants.current_view();
        if self.selection.is_some() && workspace.is_none() {
            state.projection.publish(None);
        } else {
            state
                .projection
                .replace_history(workspace, self.view.clone(), transcript);
        }
    }
}

fn transcript_id(turn: &str, item: &str) -> String {
    format!("{turn}/{item}")
}

fn read_turn(turn: &HistoryTurn, active: &mut Vec<String>) -> Vec<TranscriptItem> {
    let completed = turn.activity.status != TurnStatus::InProgress;
    turn.items
        .iter()
        .filter_map(|value| {
            let item = read_item(&turn.activity.id.0, value, completed)?;
            if !completed && item.role == TranscriptRole::Assistant {
                active.push(item.item_id.clone());
            }
            Some(item)
        })
        .collect()
}

fn read_item(turn: &str, value: &Value, completed: bool) -> Option<TranscriptItem> {
    let id = value["id"].as_str()?;
    let (role, text) = match value["type"].as_str()? {
        "agentMessage" => (
            TranscriptRole::Assistant,
            value["text"].as_str()?.to_owned(),
        ),
        "userMessage" => (
            TranscriptRole::User,
            value["content"]
                .as_array()?
                .iter()
                .filter(|entry| entry["type"] == "text")
                .filter_map(|entry| entry["text"].as_str())
                .collect::<Vec<_>>()
                .join("\n"),
        ),
        _ => return None,
    };
    Some(TranscriptItem {
        item_id: transcript_id(turn, id),
        text,
        completed,
        role,
    })
}

fn report(error: Failure) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
