use std::{
    collections::HashMap,
    error::Error,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, atomic::AtomicBool},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{
        AppServerClient, AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable,
        HistoryTurn, LoginCompletion, ServerEvent, TurnStatus,
    },
    git::turn_edits::{LastTurnView, TurnEditReports},
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    ipc::{
        ChatRow, DraftEdit, EditorDraft, IpcError, NavigationIntent, NavigationView, StreamChange,
        TextBatcher, TranscriptItem, TranscriptRole, TranscriptView, WorkspaceId, WorkspaceRequest,
        WriteAccess, present_question_reply,
    },
    storage::{
        attachments::{AttachmentStore, navigation::DesktopSelection},
        drafts::DraftId,
    },
    workspace::{
        PrepareThread, ResumedMode, RoutedEvent, RuntimeOwners, RuntimeUse, WorkspaceEngine,
    },
};
use serde_json::Value;
use tokio::{
    sync::{mpsc, oneshot},
    time::MissedTickBehavior,
};
use uuid::Uuid;

use crate::{fixture::Verification, project_ipc::ProjectState};

mod account;
mod interactions;
mod ownership;
mod parked;
mod queue;
mod quit;
mod sandbox;
mod send;
use account::AccountFlow;
use interactions::InteractionProjection;
use parked::ParkedRuntime;
use queue::{QueueCompletion, Queues};
use quit::Quit;
use sandbox::SandboxSetup;
use send::{InflightSend, SendCompletion};

const RPC_TIMEOUT: Duration = Duration::from_secs(10);
type Failure = Box<dyn Error + Send + Sync>;
type Outcome = Result<Option<WorkspaceId>, IpcError>;

#[derive(Clone)]
pub struct NavigationHandle(mpsc::Sender<Message>);

struct Message {
    action: Action,
    reply: oneshot::Sender<Outcome>,
}

enum Action {
    SelectFolder(PathBuf),
    Intent(NavigationIntent),
    RequestQuit(tauri::AppHandle),
}

enum Input {
    Command(Option<Message>),
    Backend(Option<ServerEvent>),
    SendCompleted(Option<Box<SendCompletion>>),
    QueueCompleted(Option<Box<QueueCompletion>>),
    OwnerChanged,
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
    effects: mpsc::Receiver<PrepareThread>,
    edits: TurnEditReports,
}

struct Navigation {
    store: AttachmentStore,
    owners: RuntimeOwners,
    source_draft: DraftId,
    model: Arc<Mutex<ProjectState>>,
    selection: Option<Selection>,
    backend: Option<Backend>,
    parked: HashMap<CheckoutIdentity, ParkedRuntime>,
    owner_changes: mpsc::Sender<()>,
    shutdown_pending: Arc<AtomicBool>,
    source_session: CheckoutSessionId,
    source_generation: u64,
    login: AccountFlow,
    windows_sandbox: bool,
    sandbox_setup: Option<SandboxSetup>,
    send_completions: mpsc::Sender<Box<SendCompletion>>,
    inflight: HashMap<DraftId, InflightSend>,
    queues: Queues,
    queue_completions: mpsc::Sender<Box<QueueCompletion>>,
    interactions: InteractionProjection,
    view: NavigationView,
    editable: HashMap<DraftId, Option<CheckoutIdentity>>,
    failed_drafts: HashMap<DraftId, Option<RuntimeUse>>,
    quit: Option<Quit>,
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
        verification: Verification,
    ) -> Result<Self, Failure> {
        let store = AttachmentStore::open(database)?;
        let saved = store.desktop_selection()?;
        let (sender, receiver) = mpsc::channel(32);
        let (send_completions, finished_sends) = mpsc::channel(32);
        let (queue_completions, finished_queue_jobs) = mpsc::channel(32);
        let (owner_changes, changed_owners) = mpsc::channel(1);
        let navigation = Navigation {
            owners: RuntimeOwners::new(store.clone()),
            store,
            source_draft: saved.source_draft,
            model,
            selection: None,
            backend: None,
            parked: HashMap::new(),
            owner_changes,
            shutdown_pending: Arc::default(),
            source_session: CheckoutSessionId(Uuid::new_v4()),
            source_generation: 0,
            login: AccountFlow::new(verification == Verification::Account),
            windows_sandbox: cfg!(windows) || verification == Verification::WindowsSetup,
            sandbox_setup: None,
            send_completions,
            inflight: HashMap::new(),
            queues: Queues::default(),
            queue_completions,
            interactions: InteractionProjection::default(),
            view: NavigationView::default(),
            editable: HashMap::new(),
            failed_drafts: HashMap::new(),
            quit: None,
            stream: TextBatcher::default(),
            restored_active_items: Vec::new(),
        };
        tauri::async_runtime::spawn(navigation.run(
            saved,
            fixture_project,
            receiver,
            finished_sends,
            finished_queue_jobs,
            changed_owners,
        ));
        Ok(Self(sender))
    }

    pub async fn select(&self, folder: PathBuf) -> Outcome {
        self.request(Action::SelectFolder(folder)).await
    }

    pub async fn apply(&self, intent: NavigationIntent) -> Result<(), IpcError> {
        self.request(Action::Intent(intent)).await.map(|_| ())
    }

    pub async fn request_quit(&self, app: tauri::AppHandle) -> Result<(), IpcError> {
        self.request(Action::RequestQuit(app)).await.map(|_| ())
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
        mut finished_sends: mpsc::Receiver<Box<SendCompletion>>,
        mut finished_queue_jobs: mpsc::Receiver<Box<QueueCompletion>>,
        mut changed_owners: mpsc::Receiver<()>,
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
                    completion = finished_sends.recv() => Input::SendCompleted(completion),
                    completion = finished_queue_jobs.recv() => Input::QueueCompleted(completion),
                    _ = changed_owners.recv() => Input::OwnerChanged,
                    event = backend.connection.next_event() => Input::Backend(event),
                }
            } else {
                tokio::select! {
                    _ = timer.tick(), if self.draining_quit() => Input::Flush,
                    request = commands.recv() => Input::Command(request),
                    completion = finished_sends.recv() => Input::SendCompleted(completion),
                    completion = finished_queue_jobs.recv() => Input::QueueCompleted(completion),
                    _ = changed_owners.recv() => Input::OwnerChanged,
                }
            };
            match input {
                Input::Command(Some(message)) => {
                    let result = self.handle(message.action).await;
                    let _ = message.reply.send(result);
                }
                Input::Command(None) => break,
                Input::SendCompleted(Some(result)) => self.complete_send(*result),
                Input::SendCompleted(None) => unreachable!("navigation owns the completion sender"),
                Input::QueueCompleted(Some(result)) => self.complete_queue(*result),
                Input::QueueCompleted(None) => {
                    unreachable!("navigation owns the queue completion sender")
                }
                Input::OwnerChanged => self.sync_actions(),
                Input::Backend(Some(event)) => {
                    if let Err(error) = self.handle_backend(event).await {
                        eprintln!("{error}");
                    }
                }
                Input::Backend(None) => {
                    self.flush_stream();
                    self.disconnect().await;
                }
                Input::Flush => {
                    self.flush_stream();
                    self.expire_sandbox_setup(tokio::time::Instant::now()).await;
                }
            }
            if self.advance_quit().await {
                break;
            }
        }
        self.disconnect().await;
        self.stop_parked().await;
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
            Action::RequestQuit(app) => {
                self.begin_quit(app);
                return Ok(None);
            }
            Action::SelectFolder(folder) => {
                if self.quit.is_some() {
                    return Err(IpcError::StaleSelection);
                }
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
        if self.draining_quit()
            || (self.quit.is_some()
                && !matches!(
                    &action,
                    NavigationIntent::EditDraft(_)
                        | NavigationIntent::CancelQuit(_)
                        | NavigationIntent::ConfirmQuit(_)
                ))
        {
            return Err(IpcError::StaleSelection);
        }
        match action {
            NavigationIntent::ConfirmQuit(decision) => self.confirm_quit(decision).await?,
            NavigationIntent::CancelQuit(decision) => self.cancel_quit(decision)?,
            NavigationIntent::StopAll => self.begin_stop_all(),
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
                if self.view.write_access != WriteAccess::Ready
                    || !self.view.retryable
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
            NavigationIntent::SetupSandbox(request) => {
                self.require_request(request)?;
                self.start_sandbox_setup().await?;
            }
            NavigationIntent::Send(request) => self.send_visible(request).await?,
            NavigationIntent::Queue(request) => self.handle_queue(request)?,
            NavigationIntent::Stop(request) => {
                self.require_request(WorkspaceRequest {
                    workspace_id: request.workspace_id,
                })?;
                self.stop(request.target).await.map_err(report)?;
            }
            NavigationIntent::Respond(request) => self.respond(request).await?,
            NavigationIntent::RecoverSend(request) => {
                self.require(request.workspace_id)?;
                if !self.view.actions.recover
                    || self
                        .view
                        .draft
                        .as_ref()
                        .is_none_or(|draft| draft.id != request.draft_id)
                {
                    return Err(IpcError::StaleSelection);
                }
                self.recover_send().await.map_err(report)?;
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
        self.leave_checkout().await;
        self.backend = self.take_parked(&checkout).await;
        let existing = self
            .backend
            .as_ref()
            .map(|backend| backend.engine.snapshot());
        let id = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .select_checkout(&folder, checkout.clone());
        self.selection = Some(Selection {
            id,
            session: existing.as_ref().map_or_else(
                || CheckoutSessionId(Uuid::new_v4()),
                |state| state.connection.workspace.session,
            ),
            generation: existing
                .as_ref()
                .map_or(0, |state| state.connection.generation.0),
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
        self.leave_checkout().await;
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
        self.view.actions = Default::default();
        self.view.queue = None;
        self.view.last_turn = self.last_turn_view();
        self.refresh_recovery_action();
        self.publish_history(TranscriptView::default());
        self.sync_actions();
        Ok(())
    }

    fn set_editor(&mut self, draft: DraftId) -> Result<(), Failure> {
        let text = self.store.read_editor_draft(draft)?.text;
        let checkout = self
            .selection
            .as_ref()
            .filter(|_| draft != self.source_draft)
            .map(|selection| selection.checkout.clone());
        self.editable.insert(draft, checkout);
        self.view.draft = Some(EditorDraft {
            id: draft.0.to_string(),
            text,
        });
        Ok(())
    }

    fn edit(&mut self, edit: DraftEdit) -> Result<(), IpcError> {
        let id = DraftId(Uuid::parse_str(&edit.draft_id).map_err(|_| IpcError::StaleSelection)?);
        let checkout = self.editable.get(&id).ok_or(IpcError::StaleSelection)?;
        let lease = checkout
            .as_ref()
            .map(|checkout| self.owners.acquire_write(checkout))
            .transpose()
            .map_err(|error| report(error.into()))?;
        if let Err(error) = self.store.save_editor_text(id, edit.text.clone()) {
            self.failed_drafts.entry(id).or_insert(lease);
            return Err(report(error.into()));
        }
        self.failed_drafts.remove(&id);
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
        self.sandbox_setup = None;
        self.queues = Queues::default();
        let had_write_access =
            std::mem::take(&mut self.view.write_access) != WriteAccess::Unavailable;
        if let Some(backend) = self.backend.take() {
            if let Err(error) = self.login.retire(&backend.connection.client()).await {
                eprintln!("{error}");
            }
            if self.view.account.login_ticket.take().is_some() || had_write_access {
                self.sync_actions();
            }
            parked::close_backend(&self.owners, backend).await;
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
            let (engine, effects) = WorkspaceEngine::start(identity.clone());
            if identity.workspace.checkout.is_some() {
                self.owners.register(engine.clone())?;
            }
            let client = connection.client();
            self.backend = Some(Backend {
                connection,
                engine,
                effects,
                edits: TurnEditReports::new(identity),
            });
            self.recover_hidden_owners(client);
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
        self.sync_actions();
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
        self.refresh_write_access(&client).await;
        self.refresh_recovery_action();
        self.sync_actions();
        let browser = CodexBrowser::new(client);
        let chats = browser.project_chats(false, None, RPC_TIMEOUT).await?;
        self.view.chats = chats
            .data
            .into_iter()
            .map(|chat| {
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
                ChatRow {
                    id: chat.id.0,
                    title,
                    preview,
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
        self.owners
            .reconcile_history(client.identity(), &thread, &page.data)?;
        if let Some(backend) = self.backend.as_mut() {
            backend
                .edits
                .apply_latest_history(client.identity(), &thread, &page.data);
        }
        let mut active = Vec::new();
        let mut before_resume = TranscriptView::default();
        for turn in page.data.iter().rev() {
            before_resume.items.extend(read_turn(turn, &mut active));
        }
        self.stream = TextBatcher::default();
        self.restored_active_items = active;
        self.publish_history(before_resume);

        let backend = self.backend.as_mut().expect("backend connected");
        if self.view.write_access == WriteAccess::Ready
            && (acquire_writer || !self.view.retryable)
            && !backend.engine.snapshot().writable_threads.contains(&thread)
        {
            let resumed = backend
                .engine
                .resume_thread(&mut backend.connection, &self.store, &thread, RPC_TIMEOUT)
                .await?;
            self.view.retryable = matches!(resumed.mode, ResumedMode::ReadOnly);
            if let ResumedMode::Writable { queue, .. } = resumed.mode {
                match queue {
                    Ok(queue) => self.queues.accept(thread.clone(), queue),
                    Err(error) => eprintln!("{error}"),
                }
            }
            for event in resumed.events {
                self.present_event(event);
            }
        }
        if self.view.write_access == WriteAccess::Ready && !self.queues.knows(&thread) {
            self.refresh_queue(thread);
        }
        self.sync_actions();
        Ok(())
    }

    async fn handle_backend(&mut self, event: ServerEvent) -> Result<(), Failure> {
        let Some(backend) = &mut self.backend else {
            return Ok(());
        };
        let client = backend.connection.client();
        if let ServerEvent::Notification { method, params } = &event
            && method == "windowsSandbox/setupCompleted"
        {
            let completed = serde_json::from_value(params.clone())?;
            return self
                .handle_sandbox_completion(client.identity(), completed)
                .await;
        }
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
        let update_controls = match &event {
            ServerEvent::Request { .. } => true,
            ServerEvent::Notification { method, .. } => matches!(
                method.as_str(),
                "turn/started" | "turn/completed" | "serverRequest/resolved"
            ),
        };
        let sent_message = matches!(&event, ServerEvent::Notification { method, params }
            if matches!(method.as_str(), "item/started" | "item/completed")
            && params["item"]["type"] == "userMessage"
            && params["item"]["clientId"].is_string());
        let starting_thread = match &event {
            ServerEvent::Notification { method, params } if method == "turn/started" => {
                params["threadId"]
                    .as_str()
                    .map(|thread| ThreadId(thread.into()))
            }
            _ => None,
        };
        let before = backend.engine.snapshot();
        backend.observe_edits(&event);
        let routed = backend
            .engine
            .route_session_event(&client, &self.store, event, RPC_TIMEOUT)
            .await?;
        if client.identity().workspace.checkout.is_some()
            && before.execution != backend.engine.snapshot().execution
            && let Err(error) = self
                .owners
                .record_execution(client.identity(), &before.execution)
        {
            eprintln!("{error}");
        }
        if let Some(event) = routed {
            self.present_event(event);
        }
        if let Some(thread) = starting_thread
            && !self.queues.knows(&thread)
        {
            self.refresh_queue(thread);
        }
        if sent_message {
            if let Some(draft) = self.editor_id() {
                self.refresh_draft_after_submission(draft);
            }
        } else if update_controls || self.view.last_turn != self.last_turn_view() {
            self.sync_actions();
        }
        Ok(())
    }

    fn present_event(&mut self, event: RoutedEvent) {
        if let RoutedEvent::QueueChanged(thread) = &event {
            self.refresh_queue(thread.clone());
            return;
        }
        let RoutedEvent::Conversation {
            thread,
            event: ServerEvent::Notification { method, params },
        } = event
        else {
            return;
        };
        if method == "turn/completed" && params["turn"]["status"] == "completed" {
            self.advance_legacy_queue(thread.clone());
        }
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
            "item/started" | "item/completed" => {
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

impl Backend {
    fn observe_edits(&mut self, event: &ServerEvent) {
        if let ServerEvent::Notification { params, .. } = event
            && let Some(thread) = params["threadId"].as_str()
        {
            let state = self.engine.snapshot();
            if state.writable_threads.iter().any(|owned| owned.0 == thread) {
                self.edits.observe(&state.connection, event);
            }
        }
    }
}

impl Navigation {
    fn last_turn_view(&self) -> Option<LastTurnView> {
        let thread = self.selection.as_ref()?.thread.as_ref()?;
        self.backend.as_ref()?.edits.view(thread)
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
    let text = if role == TranscriptRole::User {
        present_question_reply(&text).into_owned()
    } else {
        text
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
