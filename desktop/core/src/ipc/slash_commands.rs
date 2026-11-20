use serde::{Deserialize, Serialize};
use ts_rs::TS;

use crate::slash_commands::Command;

use super::SendRequest;

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SlashCommandView {
    pub available: Vec<Command>,
    pub plan: bool,
    pub recover_plan: bool,
    pub context: Option<ContextUsage>,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ContextUsage {
    pub tokens: u32,
    pub window: Option<u32>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecuteSlashCommand {
    pub draft: SendRequest,
    pub choice: Option<String>,
    pub confirmed: bool,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum SlashCommandOutcome {
    Send,
    Applied,
    Present(Command),
}
