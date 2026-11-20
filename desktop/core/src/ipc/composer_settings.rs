use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

use super::DraftAttachmentScope;

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ComposerPermissions {
    #[default]
    Configured,
    AskForApproval,
    ApproveForMe,
    FullAccess,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerSelection {
    pub model_id: Option<String>,
    pub effort: Option<String>,
    pub service_tier: Option<String>,
    pub permissions: ComposerPermissions,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ComposerSelectionView {
    pub revision: Uuid,
    pub selection: ComposerSelection,
    pub effective_model_id: Option<String>,
    pub default_model_id: Option<String>,
    pub uses_project_defaults: bool,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ComposerSettingsRequest {
    pub scope: DraftAttachmentScope,
    pub revision: Uuid,
    pub selection: ComposerSelection,
    pub confirm_full_access: bool,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ModelEffort {
    pub reasoning_effort: String,
    pub description: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ModelServiceTier {
    pub id: String,
    pub name: String,
}
