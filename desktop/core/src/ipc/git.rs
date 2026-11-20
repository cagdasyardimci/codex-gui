use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::WorkspaceId;

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffFileView {
    pub file_id: String,
    pub path: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffPatchRequest {
    pub workspace_id: WorkspaceId,
    pub file_id: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffPatchView {
    pub file_id: String,
    pub text: String,
}
