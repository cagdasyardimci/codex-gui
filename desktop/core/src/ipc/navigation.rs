use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use crate::git::turn_edits::LastTurnView;

use super::{
    ComposerSelectionView, ComposerSettingsRequest, ConversationActions, DraftAttachmentView,
    ModelEffort, ModelServiceTier, ProjectContextRequest, QueueRequest, QueueView, RecoverFork,
    RecoverSendRequest, RespondRequest, ResponseBookmarkRequest, ReviseSentPrompt, SendRequest,
    SlashCommandView, StopRequest, TranscriptRowRequest, WorkspaceId, WorkspaceRequest,
};

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct NavigationView {
    pub chats: Vec<ChatRow>,
    pub sidebar: super::SidebarView,
    pub selected_chat: Option<String>,
    pub draft: Option<EditorDraft>,
    pub composer_settings: Option<ComposerSelectionView>,
    pub hidden_reasoning_efforts: Vec<String>,
    pub project_has_input: bool,
    pub voice_available: bool,
    pub slash_commands: SlashCommandView,
    pub can_edit_sent_prompt: bool,
    pub literal_fork_revision: bool,
    pub bookmarked_responses: Vec<String>,
    pub can_fork: bool,
    pub recover_fork: bool,
    pub inspector: super::InspectorView,
    pub feedback: super::FeedbackView,
    pub file_revision: u32,
    pub saving_files: bool,
    pub retryable: bool,
    pub account: AccountView,
    pub write_access: WriteAccess,
    pub actions: ConversationActions,
    pub queue: Option<QueueView>,
    pub last_turn: Option<LastTurnView>,
    pub older_history: Option<OlderHistoryView>,
    pub turn_rail: Option<TurnRailView>,
    pub quit: Option<QuitView>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct OlderHistoryView {
    pub ticket: Uuid,
    pub pending: bool,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OlderHistoryRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub ticket: Uuid,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptViewportRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub rail_id: Uuid,
    pub anchor_turn: Option<String>,
    pub protected_turns: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TurnRailView {
    pub id: Uuid,
    pub turns: Vec<TurnReferenceView>,
    pub earlier: Option<Uuid>,
    pub preview: Option<TurnPreview>,
    pub jump: Option<TurnJump>,
    pub pending_jump: Option<TurnJump>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TurnReferenceView {
    pub id: String,
    pub title: Option<String>,
    pub finished: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TurnPreview {
    pub turn_id: String,
    pub prompt: Option<String>,
    pub response: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TurnJump {
    pub ticket: Uuid,
    pub turn_id: String,
    pub item_id: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TurnRailRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub rail_id: Uuid,
    pub turn_id: String,
}

#[derive(Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TurnRailTicketRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub rail_id: Uuid,
    pub ticket: Uuid,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct QuitView {
    pub ticket: String,
    pub confirm: bool,
    pub draining: bool,
    pub stop_only: bool,
    pub file_action: Option<super::FileQuitAction>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuitDecision {
    pub ticket: String,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum WriteAccess {
    #[default]
    Unavailable,
    SetupSandbox,
    UpdateSandbox,
    SettingUpSandbox,
    UpdatingSandbox,
    Ready,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AccountView {
    pub login_ticket: Option<String>,
    pub identity: Option<String>,
    pub models: Vec<AccountModel>,
    pub permits_turns: bool,
    pub chatgpt: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AccountModel {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub model: String,
    pub efforts: Vec<ModelEffort>,
    pub default_effort: Option<String>,
    pub service_tiers: Vec<ModelServiceTier>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LoginScope {
    pub workspace_id: Option<WorkspaceId>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LoginTicket {
    pub ticket: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ChatRow {
    pub id: String,
    pub title: String,
    pub preview: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct EditorDraft {
    pub id: String,
    pub text: String,
    pub attachments: Vec<DraftAttachmentView>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DraftEdit {
    pub draft_id: String,
    pub text: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum NavigationIntent {
    Sidebar(super::SidebarRequest),
    RestoreArchive(super::RestoreArchive),
    ConfirmChatDeletion(Uuid),
    CancelChatDeletion(Uuid),
    CloseMessageSearch(Uuid),
    OpenMessageSearchHit(super::MessageSearchHitRequest),
    CloseChildHistory(super::ChildHistoryTarget),
    SubmitFeedback(super::FeedbackRequest),
    StartReview(super::StartReviewRequest),
    SetComposerSettings(ComposerSettingsRequest),
    EditProjectContext(ProjectContextRequest),
    ReviseSentPrompt(ReviseSentPrompt),
    CancelSentPromptEdit(Uuid),
    SetResponseBookmark(ResponseBookmarkRequest),
    BranchResponse(TranscriptRowRequest),
    ForkChat(ChatRequest),
    RecoverFork(RecoverFork),
    OpenChat(ChatRequest),
    LoadOlderHistory(OlderHistoryRequest),
    TranscriptViewport(TranscriptViewportRequest),
    LoadTurnReferences(TurnRailTicketRequest),
    PreviewTurn(TurnRailRequest),
    CancelTurnPreview(TurnRailRequest),
    JumpToTurn(TurnRailRequest),
    CancelTurnJump(TurnRailTicketRequest),
    NewChat(WorkspaceRequest),
    ClearProject(WorkspaceRequest),
    Refresh(WorkspaceRequest),
    Reconnect(WorkspaceRequest),
    Retry(ChatRequest),
    EditDraft(DraftEdit),
    SignIn(LoginScope),
    CancelSignIn(LoginTicket),
    SetupSandbox(WorkspaceRequest),
    Send(SendRequest),
    Stop(StopRequest),
    StopAll,
    Queue(QueueRequest),
    Respond(RespondRequest),
    RecoverSend(RecoverSendRequest),
    ConfirmQuit(QuitDecision),
    CancelQuit(QuitDecision),
}
