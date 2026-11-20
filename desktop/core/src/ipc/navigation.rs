use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use crate::git::turn_edits::LastTurnView;

use super::{
    ConversationActions, QueueRequest, QueueView, RecoverSendRequest, RespondRequest, SendRequest,
    StopRequest, WorkspaceId, WorkspaceRequest,
};

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct NavigationView {
    pub chats: Vec<ChatRow>,
    pub selected_chat: Option<String>,
    pub draft: Option<EditorDraft>,
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
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AccountModel {
    pub id: String,
    pub name: String,
    pub is_default: bool,
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
    OpenChat(ChatRequest),
    LoadOlderHistory(OlderHistoryRequest),
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
