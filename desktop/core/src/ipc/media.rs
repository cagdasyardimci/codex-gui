use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::TranscriptRowRequest;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptAttachment {
    pub id: u32,
    pub label: String,
    #[serde(skip)]
    #[ts(skip)]
    pub relative_path: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptMediaRequest {
    pub row: TranscriptRowRequest,
    pub attachment_id: u32,
}
