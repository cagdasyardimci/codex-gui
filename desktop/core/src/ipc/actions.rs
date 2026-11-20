use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::WorkspaceId;

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ConversationActions {
    pub send: bool,
    pub stop: Option<StopTarget>,
    pub stop_all: bool,
    pub recover: bool,
    pub interactions: Vec<InteractionView>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum StopTarget {
    Turn(TurnTarget),
    Submission(String),
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TurnTarget {
    pub thread_id: String,
    pub turn_id: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StopRequest {
    pub workspace_id: WorkspaceId,
    pub target: StopTarget,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: Option<String>,
    pub draft_id: String,
    pub text: String,
    #[serde(default)]
    pub attachment_ids: Vec<String>,
    pub composer_revision: Option<Uuid>,
    pub expected_turn: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoverSendRequest {
    pub workspace_id: WorkspaceId,
    pub draft_id: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct InteractionView {
    pub id: String,
    pub content: InteractionContent,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum InteractionContent {
    Approval(ApprovalView),
    Permissions(PermissionView),
    Questions(Vec<QuestionView>),
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalView {
    pub request: String,
    pub choices: Vec<ApprovalChoice>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalChoice {
    pub index: u32,
    pub label: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct PermissionView {
    pub request: Option<String>,
    pub permissions: Vec<PermissionChoice>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct PermissionChoice {
    pub key: String,
    pub label: String,
    pub detail: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct QuestionView {
    pub id: String,
    pub prompt: String,
    pub options: Vec<String>,
    pub accepts_text: bool,
    pub secret: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuestionAnswer {
    pub id: String,
    pub values: Vec<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GrantedPermissions {
    pub keys: Vec<String>,
    pub for_session: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum InteractionAnswer {
    Decision(u32),
    Permissions(GrantedPermissions),
    Answers(Vec<QuestionAnswer>),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RespondRequest {
    pub workspace_id: WorkspaceId,
    pub interaction_id: String,
    pub response: InteractionAnswer,
}
