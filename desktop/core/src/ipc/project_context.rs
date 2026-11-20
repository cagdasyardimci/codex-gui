use serde::Deserialize;
use ts_rs::TS;
use uuid::Uuid;

use crate::storage::project_context::{ProjectContextItemKind, ProjectModelPreference};

use super::{DraftAttachmentScope, TranscriptRowRequest};

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectContextRequest {
    pub scope: DraftAttachmentScope,
    pub revision: u32,
    pub change: ProjectContextChange,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ProjectContextChange {
    SaveItem(ProjectItemEdit),
    RemoveItem(String),
    IncludeItem(ProjectItemInclusion),
    SavePrompt(ProjectPromptEdit),
    RemovePrompt(String),
    SetSkill(Option<Uuid>),
    SetModel(Option<ProjectModelPreference>),
    InsertPrompt(InsertProjectPrompt),
    OpenBookmark(String),
    RemoveBookmark(String),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResponseBookmarkRequest {
    pub row: TranscriptRowRequest,
    pub bookmarked: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectItemEdit {
    pub id: Option<String>,
    pub kind: ProjectContextItemKind,
    pub title: String,
    pub body: String,
    pub reference_path: Option<String>,
    pub is_included: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectItemInclusion {
    pub id: String,
    pub is_included: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectPromptEdit {
    pub id: Option<String>,
    pub title: String,
    pub instructions: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InsertProjectPrompt {
    pub id: String,
    pub expected_text: String,
}
