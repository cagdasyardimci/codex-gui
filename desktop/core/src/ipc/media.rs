use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::{TranscriptRowRequest, WorkspaceId};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptAttachment {
    pub id: u32,
    pub label: String,
    pub image: bool,
    #[serde(skip)]
    #[ts(skip)]
    pub relative_path: String,
}

pub struct TranscriptAttachmentLocation {
    pub turn_id: String,
    pub path: String,
    pub label: String,
    pub image: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptMediaRequest {
    pub row: TranscriptRowRequest,
    pub attachment_id: u32,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DraftAttachmentView {
    pub id: String,
    pub label: String,
    pub image: bool,
}

#[derive(Clone, Debug, Deserialize, PartialEq, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DraftAttachmentScope {
    pub workspace_id: WorkspaceId,
    pub draft_id: String,
    pub chat_id: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DraftAttachmentRequest {
    pub scope: DraftAttachmentScope,
    pub attachment_id: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReuseAttachmentRequest {
    pub scope: DraftAttachmentScope,
    pub media: TranscriptMediaRequest,
}
