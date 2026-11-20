use serde_json::Value;

use crate::{
    identity::OperationIdentity,
    storage::{
        attachments::BlobLease,
        drafts::{DraftId, DraftRevision},
    },
};

pub struct SendDraft {
    pub id: DraftId,
    pub revision: DraftRevision,
    pub text: String,
    pub context: Vec<Value>,
    pub attachments: Vec<BlobLease>,
}

impl SendDraft {
    pub(super) fn has_content(&self) -> bool {
        !self.text.trim().is_empty() || !self.context.is_empty() || !self.attachments.is_empty()
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SendSettings {
    pub model: Option<String>,
    pub reasoning_effort: Option<String>,
    pub service_tier: Option<String>,
    pub approval_policy: Option<Value>,
    pub approvals_reviewer: Option<String>,
    pub sandbox_policy: Option<Value>,
    pub collaboration_mode: Option<Value>,
}

pub struct SendIntent {
    pub operation: OperationIdentity,
    pub draft: SendDraft,
    pub settings: SendSettings,
}
