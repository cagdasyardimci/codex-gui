use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SentPromptEdit {
    pub ticket: Uuid,
    pub text: String,
    pub attachments: Vec<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReviseSentPrompt {
    pub ticket: Uuid,
    pub text: String,
}
