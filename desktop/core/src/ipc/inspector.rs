use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::{ChatRequest, TranscriptItem};

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct InspectorView {
    pub sources: Vec<InspectorSource>,
    pub agents: Vec<InspectorAgent>,
    pub child_revision: u32,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct InspectorSource {
    pub id: String,
    pub revision: Uuid,
    pub label: String,
    pub category: String,
    pub has_detail: bool,
    pub can_open: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct InspectorAgent {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InspectorSourceRequest {
    pub scope: ChatRequest,
    pub source_id: String,
    pub revision: Uuid,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChildHistoryRequest {
    pub target: ChildHistoryTarget,
    pub action: ChildHistoryAction,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChildHistoryTarget {
    pub scope: ChatRequest,
    pub agent_id: String,
    pub selection: Uuid,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ChildHistoryAction {
    Open,
    Refresh,
    Earlier(Uuid),
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ChildHistoryPage {
    pub rows: Vec<TranscriptItem>,
    pub earlier: Option<Uuid>,
}
