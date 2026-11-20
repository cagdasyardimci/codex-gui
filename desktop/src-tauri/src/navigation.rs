use std::{
    collections::{HashMap, HashSet},
    error::Error,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, atomic::AtomicBool},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{
        AppServerClient, AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable,
        LoginCompletion, ServerEvent, TurnStatus,
    },
    git::turn_edits::{LastTurnView, TurnEditReports, TurnEdits},
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    ipc::{
        CommandUpdate, DictationEvent, DictationTarget, DraftAttachmentScope, DraftEdit,
        EditorDraft, IpcError, NavigationIntent, NavigationView, PrepareVoiceCall,
        RemoteHostCommand, RemoteHostView, SidebarChatKey, SpeechEvent, StreamChange, TextBatcher,
        TranscriptRowRequest, TranscriptView, VoiceCallView, WorkspaceId, WorkspaceRequest,
        WriteAccess,
    },
    storage::{
        attachments::{AttachmentStore, navigation::DesktopSelection},
        drafts::DraftId,
    },
    workspace::{
        PrepareThread, ResumedMode, RoutedEvent, RuntimeOwners, RuntimeUse, WorkspaceEngine,
    },
};
use tauri::{Manager, ipc::Channel};
use tokio::{
    sync::{mpsc, oneshot},
    time::MissedTickBehavior,
};
use uuid::Uuid;

use crate::{
    dictation_ipc::QuestionDictation,
    file_search_ipc::PreparedFileHit,
    fixture::Verification,
    project_ipc::ProjectState,
    relay_ipc::RelayHost,
    speech_ipc::{Speak, SpeechOwner, SpeechPlayback, response_text},
};

mod account;
mod archive;
mod automatic_titles;
mod chat_deletion;
mod composer_attachments;
mod composer_settings;
mod conversation_fork;
mod feedback;
mod file_tools;
pub(crate) use composer_attachments::Mutation as ComposerAttachmentMutation;
pub(crate) use file_tools::FileTabCapture;
mod inspector;
mod interactions;
mod message_search;
mod ownership;
mod paging;
mod parked;
mod project_context;
mod prompt_revision;
mod queue;
mod quit;
mod relay;
mod review;
mod sandbox;
mod send;
mod sidebar;
mod slash_commands;
mod transcript;
mod voice;
use account::AccountFlow;
use interactions::InteractionProjection;
use paging::{HistoryCompletion, HistoryPaging};
use parked::ParkedRuntime;
use queue::{QueueCompletion, Queues};
use quit::Quit;
use sandbox::SandboxSetup;
use send::{InflightSend, SendCompletion};
use transcript::{append_turn, command_item, message_item, transcript_id};

const RPC_TIMEOUT: Duration = Duration::from_secs(10);
type Failure = Box<dyn Error + Send + Sync>;
type Outcome = Result<Option<WorkspaceId>, IpcError>;

fn desktop_client_info() -> ClientInfo<'static> {
    ClientInfo {
        name: "codex_gui",
        title: "Codex GUI",
        version: env!("CARGO_PKG_VERSION"),
    }
}

#[derive(Clone)]
pub struct NavigationHandle(mpsc::Sender<Message>, AttachmentStore);

struct Message {
    action: Action,
    reply: oneshot::Sender<Outcome>,
}

enum Action {
    SelectFolder(PathBuf),
    Intent(NavigationIntent),
    OpenNotificationChat(SidebarChatKey),
    PrepareVoice(PrepareVoiceCall, oneshot::Sender<VoiceCallView>),
    SpeechClient(WorkspaceId, oneshot::Sender<AppServerClient>),
    ReadAloud(TranscriptRowRequest, Uuid, Channel<SpeechEvent>),
    StartQuestionDictation(DictationTarget, Uuid, Channel<DictationEvent>),
    RemoteHost(Uuid, RemoteHostCommand, oneshot::Sender<RemoteHostView>),
    VoiceTextSaved(DraftId),
    RequestQuit(tauri::AppHandle),
    FileTools(
        codex_gui_core::ipc::FileToolsRequest,
        Option<PathBuf>,
        oneshot::Sender<codex_gui_core::ipc::FileToolsView>,
    ),
    ReadFileTab(codex_gui_core::ipc::FileTabRead, oneshot::Sender<Vec<u8>>),
    CaptureFileTab(
        codex_gui_core::ipc::FileTabRead,
        bool,
        oneshot::Sender<FileTabCapture>,
    ),
    ReadLastTurnChanges(
        DraftAttachmentScope,
        oneshot::Sender<Option<Arc<TurnEdits>>>,
    ),
    SettingsSignOut(AppServerClient, codex_gui_core::codex::AccountSnapshot),
    SettingsCommitted,
    LoadReasoningVisibility,
    EditFileTab(codex_gui_core::ipc::FileTabEdit),
    SaveFileTab(
        codex_gui_core::ipc::FileTabRead,
        oneshot::Sender<codex_gui_core::ipc::FileSaveView>,
    ),
    OpenFileSearchHit(
        Box<PreparedFileHit>,
        oneshot::Sender<codex_gui_core::ipc::OpenedFileSearchHit>,
    ),
    ComposerAttachment(composer_attachments::Mutation),
    ComposerContextClient(
        codex_gui_core::ipc::DraftAttachmentScope,
        oneshot::Sender<Option<AppServerClient>>,
    ),
    SlashCommand(
        codex_gui_core::ipc::ExecuteSlashCommand,
        oneshot::Sender<codex_gui_core::ipc::SlashCommandOutcome>,
    ),
    OpenSentPrompt(
        codex_gui_core::ipc::TranscriptRowRequest,
        oneshot::Sender<codex_gui_core::ipc::SentPromptEdit>,
    ),
    SidebarProjectPath(
        codex_gui_core::ipc::SidebarProjectRequest,
        oneshot::Sender<PathBuf>,
    ),
    StartArchiveRead(
        codex_gui_core::ipc::ArchiveScope,
        oneshot::Sender<archive::ArchiveRead>,
    ),
    FinishArchiveRead(
        archive::ArchiveReadResult,
        oneshot::Sender<codex_gui_core::ipc::ArchiveCatalog>,
    ),
    PrepareChatDeletion(
        codex_gui_core::ipc::DeleteChatSource,
        oneshot::Sender<codex_gui_core::ipc::ConfirmDeleteChat>,
    ),
    OpenMessageSearch(WorkspaceId, oneshot::Sender<Uuid>),
    PrepareSearchPage(
        codex_gui_core::ipc::MessageSearchPageRequest,
        oneshot::Sender<message_search::SearchRead>,
    ),
    FinishSearchPage(
        Box<message_search::FinishedSearchRead>,
        oneshot::Sender<codex_gui_core::ipc::MessageSearchPage>,
    ),
    InspectorSource(
        codex_gui_core::ipc::InspectorSourceRequest,
        oneshot::Sender<tauri::Url>,
    ),
    InspectorSourceDetail(
        codex_gui_core::ipc::InspectorSourceRequest,
        oneshot::Sender<String>,
    ),
    PrepareChildRead(
        codex_gui_core::ipc::ChildHistoryRequest,
        oneshot::Sender<inspector::ChildRead>,
    ),
    FinishChildRead(
        Box<inspector::ChildFinished>,
        oneshot::Sender<codex_gui_core::ipc::ChildHistoryPage>,
    ),
}

enum Input {
    Command(Option<Message>),
    Backend(Option<ServerEvent>),
    SendCompleted(Option<Box<SendCompletion>>),
    QueueCompleted(Option<Box<QueueCompletion>>),
    HistoryCompleted(Option<Box<HistoryCompletion>>),
    PromptForkCompleted(Option<Box<prompt_revision::ForkCompletion>>),
    TitleCompleted(Option<automatic_titles::TitleOutcome>),
    FeedbackCompleted(Option<Box<feedback::FeedbackOutcome>>),
    ReviewCompleted(Option<Box<review::ReviewOutcome>>),
    FileSaveCompleted(Option<Box<file_tools::FileSaveCompletion>>),
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
    commands: slash_commands::CommandRuntime,
}

struct Navigation {
    app: tauri::AppHandle,
    configured_run: composer_settings::ConfiguredRun,
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
    inspector: inspector::Inspector,
    pages: HistoryPaging,
    prompt_revisions: prompt_revision::PromptRevisions,
    archive: archive::ArchiveState,
    deletion: Option<chat_deletion::CapturedDeletion>,
    deleted_chats: HashSet<ThreadId>,
    message_search: Option<message_search::SearchSession>,
    titles: automatic_titles::AutomaticTitles,
    feedback: feedback::Feedback,
    reviews: review::Reviews,
    file_tools: file_tools::FileTools,
    worktree_records: PathBuf,
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
    pub async fn prepare_voice(
        &self,
        request: PrepareVoiceCall,
    ) -> Result<VoiceCallView, IpcError> {
        let (sender, receiver) = oneshot::channel();
        self.request(Action::PrepareVoice(request, sender)).await?;
        receiver.await.map_err(|_| IpcError::ProjectUnavailable)
    }
    pub async fn open_notification_chat(&self, key: SidebarChatKey) -> Result<(), IpcError> {
        self.request(Action::OpenNotificationChat(key))
            .await
            .map(|_| ())
    }

    pub async fn last_turn_changes(
        &self,
        scope: DraftAttachmentScope,
    ) -> Result<Option<Arc<TurnEdits>>, IpcError> {
        let (reply, receive) = oneshot::channel();
        self.request(Action::ReadLastTurnChanges(scope, reply))
            .await?;
        receive.await.map_err(|_| IpcError::ProjectUnavailable)
    }

    pub fn start(
        app: tauri::AppHandle,
        database: &Path,
        model: Arc<Mutex<ProjectState>>,
        fixture_project: Option<PathBuf>,
        verification: Verification,
    ) -> Result<Self, Failure> {
        let store = AttachmentStore::open(database)?;
        let saved = store.desktop_selection()?;
        let deleted_chats = store.deleted_chats()?;
        let worktree_records = database
            .parent()
            .ok_or("missing application data folder")?
            .join("worktrees");
        let (sender, receiver) = mpsc::channel(32);
        let (send_completions, finished_sends) = mpsc::channel(32);
        let (queue_completions, finished_queue_jobs) = mpsc::channel(32);
        let (owner_changes, changed_owners) = mpsc::channel(1);
        let navigation = Navigation {
            app,
            configured_run: composer_settings::ConfiguredRun::default(),
            owners: RuntimeOwners::new(store.clone()),
            store: store.clone(),
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
            inspector: inspector::Inspector::default(),
            pages: HistoryPaging::default(),
            prompt_revisions: prompt_revision::PromptRevisions::default(),
            archive: archive::ArchiveState::default(),
            deletion: None,
            deleted_chats,
            message_search: None,
            titles: automatic_titles::AutomaticTitles::new(matches!(
                verification,
                Verification::None | Verification::AutomaticTitles
            )),
            feedback: feedback::Feedback::default(),
            reviews: review::Reviews::default(),
            file_tools: file_tools::FileTools::default(),
            worktree_records,
            view: NavigationView {
                hidden_reasoning_efforts: store.hidden_reasoning_efforts()?,
                ..NavigationView::default()
            },
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
        Ok(Self(sender, store))
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

    pub async fn speech_client(&self, workspace: WorkspaceId) -> Result<AppServerClient, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::SpeechClient(workspace, reply)).await?;
        result.await.map_err(|_| IpcError::StaleSelection)
    }

    pub async fn start_question_dictation(
        &self,
        target: DictationTarget,
        id: Uuid,
        events: Channel<DictationEvent>,
    ) -> Result<(), IpcError> {
        self.request(Action::StartQuestionDictation(target, id, events))
            .await
            .map(|_| ())
    }

    pub async fn read_aloud(
        &self,
        row: TranscriptRowRequest,
        id: Uuid,
        events: Channel<SpeechEvent>,
    ) -> Result<(), IpcError> {
        self.request(Action::ReadAloud(row, id, events))
            .await
            .map(|_| ())
    }

    pub async fn change_remote_host(
        &self,
        session: Uuid,
        command: RemoteHostCommand,
    ) -> Result<RemoteHostView, IpcError> {
        let (reply, result) = oneshot::channel();
        self.request(Action::RemoteHost(session, command, reply))
            .await?;
        result.await.map_err(|_| IpcError::StaleSelection)
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
        self.restore_relay().await;
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
                    completion = self.pages.completed.recv() => Input::HistoryCompleted(completion),
                    completion = self.prompt_revisions.completed.recv() => Input::PromptForkCompleted(completion),
                    completion = self.titles.completed.recv() => Input::TitleCompleted(completion),
                    completion = self.feedback.completed.recv() => Input::FeedbackCompleted(completion),
                    completion = self.reviews.completed.recv() => Input::ReviewCompleted(completion),
                    completion = self.file_tools.completed.recv() => Input::FileSaveCompleted(completion),
                    _ = changed_owners.recv() => Input::OwnerChanged,
                    event = backend.connection.next_event() => Input::Backend(event),
                }
            } else {
                tokio::select! {
                    _ = timer.tick(), if self.draining_quit() => Input::Flush,
                    request = commands.recv() => Input::Command(request),
                    completion = finished_sends.recv() => Input::SendCompleted(completion),
                    completion = finished_queue_jobs.recv() => Input::QueueCompleted(completion),
                    completion = self.pages.completed.recv() => Input::HistoryCompleted(completion),
                    completion = self.prompt_revisions.completed.recv() => Input::PromptForkCompleted(completion),
                    completion = self.titles.completed.recv() => Input::TitleCompleted(completion),
                    completion = self.feedback.completed.recv() => Input::FeedbackCompleted(completion),
                    completion = self.reviews.completed.recv() => Input::ReviewCompleted(completion),
                    completion = self.file_tools.completed.recv() => Input::FileSaveCompleted(completion),
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
                Input::HistoryCompleted(Some(result)) => self.complete_history_page(*result),
                Input::HistoryCompleted(None) => {
                    unreachable!("navigation owns the history completion sender")
                }
                Input::PromptForkCompleted(Some(result)) => {
                    if let Err(error) = self.complete_prompt_fork(*result).await {
                        eprintln!("{error}");
                    }
                }
                Input::PromptForkCompleted(None) => {
                    unreachable!("navigation owns the completion sender")
                }
                Input::TitleCompleted(Some(outcome)) => {
                    if let Err(error) = self.complete_automatic_title(outcome).await {
                        eprintln!("{error}");
                    }
                }
                Input::TitleCompleted(None) => unreachable!("navigation owns the title sender"),
                Input::FeedbackCompleted(Some(outcome)) => self.complete_feedback(*outcome),
                Input::FeedbackCompleted(None) => {
                    unreachable!("navigation owns the feedback sender")
                }
                Input::ReviewCompleted(Some(outcome)) => {
                    if let Err(error) = self.complete_review(*outcome) {
                        eprintln!("{error}");
                        self.sync_actions();
                    }
                }
                Input::ReviewCompleted(None) => unreachable!("navigation owns the review sender"),
                Input::FileSaveCompleted(Some(completed)) => self.finish_file_save(*completed),
                Input::FileSaveCompleted(None) => {
                    unreachable!("navigation owns the file save sender")
                }
                Input::OwnerChanged => {
                    if let Err(error) = self.reload_sidebar() {
                        eprintln!("{error}");
                    }
                    self.sync_actions();
                    self.restore_relay().await;
                }
                Input::Backend(Some(event)) => {
                    if let Err(error) = self.handle_backend(event).await {
                        eprintln!("{error}");
                    }
                }
                Input::Backend(None) => {
                    self.flush_stream();
                    self.disconnect().await;
                    self.restore_relay().await;
                }
                Input::Flush => {
                    self.flush_stream();
                    if self.inspector.flush_child() {
                        self.view.inspector = self.inspector.view();
                        self.publish_navigation();
                    }
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
        self.reload_sidebar()?;
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
            Action::OpenNotificationChat(key) => {
                if self.quit.is_some() {
                    return Err(IpcError::StaleSelection);
                }
                self.open_sidebar_chat(key).await?;
                return Ok(None);
            }
            Action::PrepareVoice(request, result) => {
                let _ = result.send(self.reserve_voice_call(request).await?);
                return Ok(None);
            }
            Action::SpeechClient(workspace, reply) => {
                self.require(workspace)?;
                let backend = self.backend.as_ref().ok_or(IpcError::StaleSelection)?;
                let _ = reply.send(backend.connection.client());
                return Ok(None);
            }
            Action::RemoteHost(session, command, reply) => {
                self.app
                    .state::<crate::settings_ipc::SettingsIpc>()
                    .authorize_session(session)?;
                if self.quit.is_some() {
                    return Err(IpcError::StaleSelection);
                }
                let _ = reply.send(self.apply_relay(command).await?);
                return Ok(None);
            }
            Action::StartQuestionDictation(target, id, events) => {
                self.require(target.workspace_id)?;
                if !self.can_dictate(&target) {
                    return Err(IpcError::StaleSelection);
                }
                self.app
                    .state::<QuestionDictation>()
                    .begin(&self.app, id, target, events);
                return Ok(None);
            }
            Action::ReadAloud(row, id, events) => {
                self.require(row.workspace_id)?;
                if self.quit.is_some() || self.backend.is_none() {
                    return Err(IpcError::StaleSelection);
                }
                let source = self
                    .model
                    .lock()
                    .expect("workspace state lock poisoned")
                    .projection
                    .transcript_markdown(&row)?;
                let text = response_text(&source)?;
                let checkout = self
                    .selection
                    .as_ref()
                    .ok_or(IpcError::RetiredWorkspace)?
                    .checkout
                    .clone();
                self.app.state::<SpeechPlayback>().begin(
                    &self.app,
                    Speak {
                        owner: SpeechOwner::Transcript,
                        id,
                        checkout,
                        voice: None,
                        text,
                        events,
                    },
                );
                return Ok(None);
            }
            Action::VoiceTextSaved(draft) => {
                self.refresh_draft_after_submission(draft);
                return Ok(None);
            }
            Action::ComposerAttachment(mutation) => {
                self.update_composer_attachments(mutation)?;
                return Ok(None);
            }
            Action::FileTools(request, path, reply) => {
                let _ = reply.send(self.change_file_tools(request, path)?);
                return Ok(None);
            }
            Action::ReadFileTab(request, reply) => {
                let _ = reply.send(self.read_file_tools(request)?);
                return Ok(None);
            }
            Action::CaptureFileTab(request, bytes, reply) => {
                let _ = reply.send(self.capture_file_tools_tab(request, bytes)?);
                return Ok(None);
            }
            Action::ReadLastTurnChanges(scope, reply) => {
                let _ = reply.send(self.read_last_turn_changes(&scope)?);
                return Ok(None);
            }
            Action::SettingsSignOut(client, account) => {
                self.apply_settings_sign_out(client, account).await?;
                return Ok(None);
            }
            Action::SettingsCommitted => {
                if let Some(backend) = &self.backend {
                    self.configured_run =
                        composer_settings::read_configured_run(backend.connection.client()).await;
                    self.reconcile_composer_models();
                    self.sync_actions();
                }
                return Ok(None);
            }
            Action::LoadReasoningVisibility => {
                self.view.hidden_reasoning_efforts = self
                    .store
                    .hidden_reasoning_efforts()
                    .map_err(|error| report(error.into()))?;
                self.publish_navigation();
                return Ok(None);
            }
            Action::EditFileTab(request) => {
                self.edit_file_tools(request)?;
                return Ok(None);
            }
            Action::SaveFileTab(request, reply) => {
                self.start_file_save(request, reply)?;
                return Ok(None);
            }
            Action::OpenFileSearchHit(hit, reply) => {
                let _ = reply.send(self.open_file_match(*hit)?);
                return Ok(None);
            }
            Action::ComposerContextClient(scope, reply) => {
                self.require(scope.workspace_id)?;
                if self.view.selected_chat != scope.chat_id
                    || self.view.draft.as_ref().map(|draft| &draft.id) != Some(&scope.draft_id)
                {
                    return Err(IpcError::StaleSelection);
                }
                let client = self
                    .backend
                    .as_ref()
                    .map(|backend| backend.connection.client());
                let _ = reply.send(client);
                return Ok(None);
            }
            Action::SlashCommand(request, reply) => {
                let outcome = self.execute_slash(request).await?;
                let _ = reply.send(outcome);
                return Ok(None);
            }
            Action::OpenSentPrompt(request, reply) => {
                let edit = self.inspect_sent_prompt(request).await?;
                let _ = reply.send(edit);
                return Ok(None);
            }
            Action::SidebarProjectPath(request, reply) => {
                let path = self.sidebar_path(request)?;
                let _ = reply.send(path);
                return Ok(None);
            }
            Action::StartArchiveRead(scope, reply) => {
                let read = self.start_archive_read(scope).await?;
                let _ = reply.send(read);
                return Ok(None);
            }
            Action::FinishArchiveRead(read, reply) => {
                let catalog = self.finish_archive_read(read)?;
                let _ = reply.send(catalog);
                return Ok(None);
            }
            Action::PrepareChatDeletion(source, reply) => {
                let deletion = self.capture_chat_deletion(source, None)?;
                let _ = reply.send(deletion);
                return Ok(None);
            }
            Action::OpenMessageSearch(workspace, reply) => {
                let _ = reply.send(self.open_message_search(workspace)?);
                return Ok(None);
            }
            Action::PrepareSearchPage(request, reply) => {
                let _ = reply.send(self.prepare_search_page(request)?);
                return Ok(None);
            }
            Action::FinishSearchPage(result, reply) => {
                let _ = reply.send(self.finish_search_page(*result)?);
                return Ok(None);
            }
            Action::InspectorSource(source, reply) => {
                let _ = reply.send(self.inspector_source_url(source)?);
                return Ok(None);
            }
            Action::InspectorSourceDetail(source, reply) => {
                let _ = reply.send(self.inspector_detail(source)?);
                return Ok(None);
            }
            Action::PrepareChildRead(request, reply) => {
                let _ = reply.send(self.prepare_child_read(request)?);
                return Ok(None);
            }
            Action::FinishChildRead(result, reply) => {
                let _ = reply.send(self.finish_child_read(*result)?);
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
            NavigationIntent::EditProjectContext(request) => {
                self.edit_project_context(request).await?
            }
            NavigationIntent::ConfirmQuit(decision) => self.confirm_quit(decision).await?,
            NavigationIntent::Sidebar(request) => self.edit_sidebar(request).await?,
            NavigationIntent::RestoreArchive(request) => self.restore_archived(request).await?,
            NavigationIntent::ConfirmChatDeletion(ticket) => {
                self.confirm_chat_deletion(ticket).await?
            }
            NavigationIntent::CancelChatDeletion(ticket) => self.cancel_chat_deletion(ticket)?,
            NavigationIntent::CloseMessageSearch(ticket) => self.close_message_search(ticket)?,
            NavigationIntent::OpenMessageSearchHit(request) => {
                self.open_message_search_hit(request).await?
            }
            NavigationIntent::CloseChildHistory(scope) => self.close_child_history(scope)?,
            NavigationIntent::SubmitFeedback(request) => self.submit_feedback(request).await?,
            NavigationIntent::StartReview(request) => self.start_review(request)?,
            NavigationIntent::ReviseSentPrompt(request) => self.revise_sent_prompt(request)?,
            NavigationIntent::CancelSentPromptEdit(ticket) => self.prompt_revisions.cancel(ticket),
            NavigationIntent::SetResponseBookmark(request) => {
                self.set_response_bookmark(request)?
            }
            NavigationIntent::BranchResponse(row) => self.branch_response(row).await?,
            NavigationIntent::ForkChat(source) => {
                self.start_conversation_fork(
                    source,
                    codex_gui_core::codex::ForkBoundary::SavedChat,
                    None,
                )
                .await?
            }
            NavigationIntent::RecoverFork(request) => {
                self.recover_conversation_fork(request).await?
            }
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
            NavigationIntent::LoadOlderHistory(request) => self.load_older_history(request)?,
            NavigationIntent::TranscriptViewport(request) => {
                self.record_transcript_viewport(request)?
            }
            NavigationIntent::LoadTurnReferences(request) => self.load_turn_references(request)?,
            NavigationIntent::PreviewTurn(request) => self.preview_turn(request)?,
            NavigationIntent::CancelTurnPreview(request) => self.cancel_turn_preview(request)?,
            NavigationIntent::JumpToTurn(request) => self.jump_to_turn(request)?,
            NavigationIntent::CancelTurnJump(request) => self.cancel_turn_jump(request)?,
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
                self.restore_relay().await;
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
            NavigationIntent::SetComposerSettings(request) => {
                self.change_composer_settings(request)?
            }
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
        self.message_search = None;
        self.retire_file_search();
        self.store.remember_sidebar_project(&checkout)?;
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
        self.view = NavigationView {
            saving_files: self.file_tools.is_saving(),
            ..NavigationView::default()
        };
        self.configured_run = composer_settings::ConfiguredRun::default();
        self.adopt_focus(thread)?;
        if let Err(error) = self.refresh().await {
            eprintln!("{error}");
        }
        Ok(id)
    }

    async fn clear(&mut self) -> Result<(), Failure> {
        self.retire_file_search();
        self.message_search = None;
        self.store.save_desktop_selection(None, None)?;
        self.leave_checkout().await;
        self.selection = None;
        self.model
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .clear();
        self.view = NavigationView {
            saving_files: self.file_tools.is_saving(),
            ..NavigationView::default()
        };
        self.configured_run = composer_settings::ConfiguredRun::default();
        self.adopt_focus(None)?;
        self.refresh().await
    }

    async fn focus(&mut self, thread: Option<ThreadId>) -> Result<(), Failure> {
        let selected = self.selection.as_ref().ok_or("missing project selection")?;
        if selected.thread == thread {
            self.clear_selected_unread()?;
            self.publish_navigation();
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
        self.retire_file_search();
        self.prompt_revisions.retire_editor();
        self.inspector = inspector::Inspector::default();
        self.view.inspector = self.inspector.view();
        let draft = match &thread {
            Some(thread) => self.store.editable_thread_draft(thread)?,
            None => self.source_draft,
        };
        self.set_editor(draft)?;
        self.view.selected_chat = thread.as_ref().map(|thread| thread.0.clone());
        self.clear_selected_unread()?;
        let context = self.project_context()?;
        self.project_context_changed(&context);
        self.load_composer_settings()?;
        self.view.retryable = false;
        self.retire_history_pages();
        if let Some(selected) = &mut self.selection {
            selected.thread = thread;
        }
        self.reload_feedback()?;
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
        let saved = self.store.read_editor_draft(draft)?;
        let checkout = self
            .selection
            .as_ref()
            .filter(|_| draft != self.source_draft)
            .map(|selection| selection.checkout.clone());
        self.editable.insert(draft, checkout);
        self.view.draft = Some(EditorDraft {
            id: draft.0.to_string(),
            text: saved.text,
            attachments: composer_attachments::views(&saved.context),
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
        self.message_search = None;
        self.inspector.close_child();
        self.view.feedback.available = false;
        self.retire_history_pages();
        self.sandbox_setup = None;
        self.queues = Queues::default();
        let had_write_access =
            std::mem::take(&mut self.view.write_access) != WriteAccess::Unavailable;
        if let Some(backend) = self.backend.take() {
            tauri::Manager::state::<crate::voice_ipc::VoiceIpc>(&self.app)
                .connection_closed(&self.app, backend.connection.client().identity());
            self.app
                .state::<RelayHost>()
                .disconnected(backend.connection.client().identity());
            self.titles
                .retire_connection(backend.connection.client().identity());
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
            let backend = self.open_backend(identity).await?;
            let client = backend.connection.client();
            self.backend = Some(backend);
            self.recover_hidden_owners(client);
        }
        let backend = self.backend.as_ref().expect("backend connected");
        Ok(backend.connection.client())
    }

    async fn open_backend(&self, identity: ConnectionIdentity) -> Result<Backend, Failure> {
        let executable = CodexExecutable::discover(None)?;
        let connection = AppServerConnection::connect(
            &executable,
            identity.clone(),
            desktop_client_info(),
            RPC_TIMEOUT,
        )
        .await?;
        let (engine, effects) = WorkspaceEngine::start(identity.clone());
        if identity.workspace.checkout.is_some() {
            self.owners.register(engine.clone())?;
        }
        Ok(Backend {
            connection,
            engine,
            effects,
            edits: TurnEditReports::new(identity),
            commands: slash_commands::CommandRuntime::default(),
        })
    }

    async fn refresh_account(&mut self, client: AppServerClient) -> Result<(), Failure> {
        let (account, configured) = tokio::join!(
            account::read_account(client.clone()),
            composer_settings::read_configured_run(client)
        );
        let mut account = account?;
        account
            .login_ticket
            .clone_from(&self.view.account.login_ticket);
        self.view.account = account;
        self.configured_run = configured;
        self.reconcile_composer_models();
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
        self.load_command_capabilities(&client).await;
        self.reload_feedback()?;
        self.refresh_write_access(&client).await;
        self.refresh_recovery_action();
        self.sync_actions();
        let browser = CodexBrowser::new(client);
        let mut cursors = HashSet::new();
        let mut ids = HashSet::new();
        let mut cursor = None;
        let mut chats = Vec::new();
        loop {
            let page = browser
                .project_chats(false, cursor.as_ref(), RPC_TIMEOUT)
                .await?;
            chats.extend(
                page.data
                    .into_iter()
                    .filter(|thread| {
                        self.archive.keep_active(&thread.id)
                            && !self.deleted_chats.contains(&thread.id)
                            && ids.insert(thread.id.clone())
                    })
                    .map(sidebar::sidebar_chat_row),
            );
            let Some(next) = page.next_cursor else { break };
            if !cursors.insert(next.clone()) {
                return Err("Codex repeated a project chat directory cursor".into());
            }
            cursor = Some(next);
        }
        let checkout = &self
            .selection
            .as_ref()
            .ok_or("missing selected project")?
            .checkout;
        self.store
            .remember_sidebar_chats(checkout, chats.iter().cloned())?;
        self.view.chats = chats.into_iter().map(|(row, _)| row).collect();
        self.clear_selected_unread()?;
        self.publish_navigation();
        self.open_history(false).await
    }

    async fn open_history(&mut self, acquire_writer: bool) -> Result<(), Failure> {
        let Some(selection) = self.selection.as_ref() else {
            return Ok(());
        };
        let Some(thread) = selection.thread.clone() else {
            return Ok(());
        };
        let checkout = selection.checkout.clone();
        let workspace = selection.id;
        self.retire_history_pages();
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
        self.inspector.history(&thread, &page.data);
        self.view.inspector = self.inspector.view();
        self.owners
            .reconcile_history(client.identity(), &thread, &page.data)?;
        if let Some(backend) = self.backend.as_mut() {
            backend
                .edits
                .apply_latest_history(client.identity(), &thread, &page.data);
        }
        let mut active = Vec::new();
        let mut before_resume = TranscriptView::default();
        let canonical_speech = summary
            .for_selection(client.identity(), &thread)?
            .thread
            .history_mode
            .as_deref()
            == Some("paginated");
        for turn in page.data.iter().rev() {
            transcript::append_turn_with_speech(
                &mut before_resume,
                &checkout,
                turn,
                &mut active,
                canonical_speech,
            );
        }
        self.stream = TextBatcher::default();
        self.restored_active_items = active;
        self.pages.install(
            workspace,
            thread.clone(),
            client.identity(),
            Some(summary),
            page,
        );
        self.view.older_history = self.pages.view();
        self.start_turn_rail(client.clone());
        self.publish_history(before_resume);
        if let Err(error) = self.start_speech_history(false) {
            eprintln!("{error:?}");
        }

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
        if self
            .app
            .state::<RelayHost>()
            .observe(&self.app, client.identity(), &event)
        {
            return Ok(());
        }
        if let ServerEvent::Notification { method, params } = &event
            && method == "thread/realtime/itemAdded"
        {
            if let Some(chat) = params["threadId"].as_str()
                && backend
                    .engine
                    .snapshot()
                    .writable_threads
                    .contains(&ThreadId(chat.into()))
                && let Some(speech) =
                    codex_gui_core::codex::VoiceSegment::from_item(&params["item"])
            {
                self.present_speech(chat, speech);
            }
            return Ok(());
        }
        let voice_turn = match &event {
            ServerEvent::Notification { method, params } if method == "turn/started" => {
                params["threadId"]
                    .as_str()
                    .zip(params["turn"]["id"].as_str())
                    .filter(|(chat, _)| {
                        tauri::Manager::state::<crate::voice_ipc::VoiceIpc>(&self.app)
                            .owns_chat(client.identity(), chat)
                    })
                    .map(|(chat, turn)| (chat.to_owned(), turn.to_owned()))
            }
            _ => None,
        };
        if tauri::Manager::state::<crate::voice_ipc::VoiceIpc>(&self.app).observe(
            &self.app,
            client.identity(),
            &event,
        ) {
            return Ok(());
        }
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
        let command_changed = if matches!(&event, ServerEvent::Notification { method, .. } if method == "thread/tokenUsage/updated")
        {
            false
        } else {
            backend.observe_slash_event(&event, &self.store)?
        };
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
        let inspector_changed = self
            .selection
            .as_ref()
            .and_then(|selection| selection.thread.as_ref())
            .is_some_and(|thread| self.inspector.event(thread, &event));
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
        if let Some((chat, turn)) = voice_turn {
            self.remember_voice_turn(&chat, &turn);
        }
        if let Some(event) = routed {
            crate::task_notifications::observe(
                &self.app,
                &self.store,
                client.identity(),
                &event,
                |chat, turn| {
                    before
                        .execution
                        .active_turns
                        .iter()
                        .any(|active| active.thread.0 == chat && active.turn.0 == turn)
                },
            );
            self.present_event(event);
        }
        if inspector_changed {
            self.view.inspector = self.inspector.view();
            self.publish_navigation();
        }
        if let Some(thread) = starting_thread
            && !self.queues.knows(&thread)
        {
            self.refresh_queue(thread);
        }
        if sent_message || command_changed {
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
        if method == "thread/tokenUsage/updated" {
            if let Some(backend) = self.backend.as_mut() {
                let event = ServerEvent::Notification { method, params };
                match backend.observe_slash_event(&event, &self.store) {
                    Ok(true) => self.sync_actions(),
                    Ok(false) => {}
                    Err(error) => eprintln!("{error}"),
                }
            }
            return;
        }
        if method == "turn/completed" && params["turn"]["status"] == "completed" {
            if let Err(error) = self.record_chat_activity(&thread) {
                eprintln!("{error}");
            }
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
                if let Some(turn) = params["turn"]["id"].as_str()
                    && let Ok(status) =
                        serde_json::from_value::<TurnStatus>(params["turn"]["status"].clone())
                    && status.is_finished()
                {
                    self.observe_rail_turn(&thread, turn, status);
                }
                self.flush_stream();
            }
            return;
        };
        let workspace = selection.id;
        let checkout = selection.checkout.clone();
        self.observe_rail_turn(&thread, turn_id, TurnStatus::InProgress);
        let voice_turn = self.voice_turn(&thread.0, turn_id);
        match method.as_str() {
            "item/agentMessage/delta" if !voice_turn => {
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
                let wire = &params["item"];
                if let Some(command) = command_item(turn_id, wire) {
                    self.flush_stream();
                    self.publish_command(workspace, command);
                } else if let Some(mut item) =
                    message_item(&checkout, turn_id, wire, method == "item/completed")
                    && (!voice_turn || item.completed && item.show_voice_response())
                {
                    if !item.completed && self.restored_active_items.contains(&item.item_id) {
                        return;
                    }
                    if item.completed {
                        self.restored_active_items.retain(|id| *id != item.item_id);
                    }
                    self.flush_stream();
                    self.publish_stream(workspace, StreamChange::FinalItem(item));
                }
            }
            "item/commandExecution/outputDelta" => {
                if let (Some(item), Some(delta)) =
                    (params["itemId"].as_str(), params["delta"].as_str())
                {
                    self.publish_command(
                        workspace,
                        CommandUpdate::Output {
                            item_id: transcript_id(turn_id, item),
                            delta: delta.to_owned(),
                        },
                    );
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

    fn publish_command(&self, workspace: WorkspaceId, change: CommandUpdate) {
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        state.publish();
        state.projection.publish_command(workspace, change);
    }

    fn publish_navigation(&self) {
        self.app
            .state::<QuestionDictation>()
            .retain(|target| self.can_dictate(target));
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
    fn read_last_turn_changes(
        &self,
        scope: &DraftAttachmentScope,
    ) -> Result<Option<Arc<TurnEdits>>, IpcError> {
        self.file_tools_key(scope)?;
        Ok(self
            .selection
            .as_ref()
            .and_then(|selection| selection.thread.as_ref())
            .and_then(|thread| self.backend.as_ref()?.edits.current(thread)))
    }

    fn last_turn_view(&self) -> Option<LastTurnView> {
        let thread = self.selection.as_ref()?.thread.as_ref()?;
        self.backend.as_ref()?.edits.view(thread)
    }
}

fn report(error: Failure) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
