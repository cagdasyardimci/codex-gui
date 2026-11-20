use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::{DraftAttachmentScope, FileEditor};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum DiffComparison {
    Uncommitted,
    Staged,
    Unstaged,
    Branch(Option<String>),
    Commit(String),
    Between { base: String, target: String },
    LastTurn,
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffChangesRequest {
    pub scope: DraftAttachmentScope,
    pub view_id: Uuid,
    pub comparison: DiffComparison,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffReference {
    pub reference: String,
    pub label: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffReferences {
    pub upstream: Option<String>,
    pub branches: Vec<DiffReference>,
    pub commits: Vec<DiffReference>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffFileView {
    pub file_id: String,
    pub path: String,
    pub renamed_from: Option<String>,
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffPatchRequest {
    pub scope: DraftAttachmentScope,
    pub file_id: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum DiffSide {
    Before,
    After,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum DiffRichKind {
    Markdown,
    Svg,
    Pdf,
    Raster,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffContentView {
    pub side: DiffSide,
    pub path: String,
    pub rich: Option<DiffRichKind>,
    pub text: Option<String>,
    pub editors: Vec<FileEditor>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DiffPatchView {
    pub file_id: String,
    pub text: String,
    pub exportable: bool,
    pub reviewed: bool,
    pub reviewed_hunks: Vec<u32>,
    pub contents: Vec<DiffContentView>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffMarkerRequest {
    pub target: DiffPatchRequest,
    pub hunk: Option<u32>,
    pub reviewed: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffMediaRequest {
    pub target: DiffPatchRequest,
    pub side: DiffSide,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum DiffAction {
    CopyPatch,
    ExportPatch,
    ExportFile(DiffSide),
    OpenEditor { side: DiffSide, editor: String },
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiffActionRequest {
    pub target: DiffPatchRequest,
    pub action: DiffAction,
}
