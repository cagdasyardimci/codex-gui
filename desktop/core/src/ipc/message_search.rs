use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::{TranscriptItem, WorkspaceId};

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MessageSearchPageRequest {
    pub session: Uuid,
    pub chat_id: String,
    pub restart: bool,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct MessageSearchPage {
    pub rows: Vec<TranscriptItem>,
    pub more: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MessageSearchHitRequest {
    pub session: Uuid,
    pub workspace_id: WorkspaceId,
    pub chat_id: String,
    pub turn_id: String,
    pub item_id: String,
}
