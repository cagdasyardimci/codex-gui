use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::{DraftAttachmentScope, WorkspaceId};
use crate::files::index::{ProjectFolderId, ProjectPathId};

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectBrowseRequest {
    pub workspace_id: WorkspaceId,
    pub folder: Option<ProjectFolderId>,
    pub offset: u32,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileToolsRequest {
    pub scope: DraftAttachmentScope,
    pub change: FileToolsChange,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum FileToolsChange {
    Inspect,
    Show(bool),
    Widen(bool),
    Open(FileTabOpen),
    Select(Uuid),
    Keep(Uuid),
    Move(FileTabMove),
    Close(Uuid),
    Discard(FileTabDiscard),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileTabOpen {
    pub path: ProjectPathId,
    pub keep: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileTabMove {
    pub tab_id: Uuid,
    pub before: Option<Uuid>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileToolsView {
    pub session_id: Uuid,
    pub open: bool,
    pub wide: bool,
    pub selected: Option<Uuid>,
    pub tabs: Vec<FileTabView>,
    pub discard: Option<FileTabDiscard>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileTabView {
    pub id: Uuid,
    pub path: String,
    pub kind: FileTabKind,
    pub preview: bool,
    pub dirty: bool,
    pub saving: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum FileTabKind {
    Text,
    Raster,
    Pdf,
    Other,
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FilePreviewRequest {
    pub target: FileTabRead,
    pub kind: FilePreviewKind,
}

#[derive(Clone, Copy, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum FilePreviewKind {
    Raster,
    Pdf,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileTabDiscard {
    pub tab_id: Uuid,
    pub revision: u32,
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileTabRead {
    pub scope: DraftAttachmentScope,
    pub tab_id: Uuid,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileSaveView {
    pub view: Option<FileToolsView>,
    pub saved: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileActionRequest {
    pub target: FileTabRead,
    pub action: FileAction,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum FileAction {
    Copy,
    Export,
    Reveal,
    OpenDefault,
    OpenEditor(String),
    OpenGitHub,
}

#[derive(Clone, Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileEditor {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileActionsView {
    pub editors: Vec<FileEditor>,
    pub github: bool,
}

#[derive(Debug, Serialize, TS)]
pub struct MarkdownFileProperty {
    pub key: String,
    pub values: Vec<String>,
}

#[derive(Debug, Serialize, TS)]
pub struct MarkdownFileView {
    pub nodes: Option<Vec<super::MarkdownNode>>,
    pub properties: Vec<MarkdownFileProperty>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileMarkdownResource {
    pub target: FileTabRead,
    pub resource: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileTabEdit {
    pub session_id: Uuid,
    pub tab_id: Uuid,
    pub text: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum FileQuitAction {
    Save,
    Discard,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartFileSearch {
    pub scope: DraftAttachmentScope,
    pub query: String,
    pub mask: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadFileSearch {
    pub session: Uuid,
    pub cursor: Option<Uuid>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileSearchPage {
    pub matches: Vec<FileSearchResult>,
    pub next_cursor: Option<Uuid>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileSearchResult {
    pub id: Uuid,
    pub path: String,
    pub line: u32,
    pub excerpt: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenFileSearchHit {
    pub session: Uuid,
    pub id: Uuid,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct OpenedFileSearchHit {
    pub view: FileToolsView,
    pub line: u32,
}
