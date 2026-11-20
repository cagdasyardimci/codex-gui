use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::WorkspaceId;

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct QueueView {
    pub revision: String,
    pub enabled: bool,
    pub busy: bool,
    pub active_turn: Option<String>,
    pub entries: Vec<QueueEntryView>,
    pub editing: Option<QueueEditView>,
    pub resume: Option<String>,
    pub saved: Vec<QueueEntryView>,
    pub resume_saved: Option<String>,
    pub recover: bool,
    pub detached: Vec<QueueEntryView>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct QueueEntryView {
    pub id: String,
    pub text: String,
    pub reserved: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct QueueEditView {
    pub id: String,
    pub has_context: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QueueRequest {
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub revision: String,
    pub command: QueueCommand,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum QueueCommand {
    Enable(bool),
    Edit(String),
    CancelEdit(String),
    SaveEdit(String),
    Reorder(Vec<String>),
    Delete(String),
    Resume(String),
    ResumeSaved(String),
    Steer(QueueSteerTarget),
    Recover,
    Restore(String),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QueueSteerTarget {
    pub entry_id: String,
    pub turn_id: String,
}
