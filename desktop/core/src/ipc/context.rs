use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::{DraftAttachmentScope, ProjectPathId};

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ComposerChoiceKind {
    Skill,
    ProjectContext,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ComposerChoice {
    pub id: Uuid,
    pub label: String,
    pub kind: ComposerChoiceKind,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerContextSelection {
    pub scope: DraftAttachmentScope,
    pub expected_text: String,
    pub replace_token: Option<ComposerTokenRange>,
    pub target: ComposerContextTarget,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerTokenRange {
    pub start: u32,
    pub end: u32,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ComposerContextTarget {
    File(ComposerFileContext),
    Catalog(Uuid),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerFileContext {
    pub path: ProjectPathId,
    pub lines: Option<ComposerSourceLines>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerSourceLines {
    pub first: u32,
    pub last: u32,
}
