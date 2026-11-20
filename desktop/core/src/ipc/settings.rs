use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsAccountView {
    pub provider: Option<String>,
    pub email: Option<String>,
    pub plan: Option<String>,
    pub can_sign_out: bool,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct UsageWindowView {
    pub name: String,
    pub minutes: Option<u32>,
    pub remaining_percent: Option<f64>,
    #[ts(type = "number | null")]
    pub resets_at: Option<i64>,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct DailyUsageView {
    pub date: String,
    #[ts(type = "number")]
    pub tokens: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct EffectiveSettingView {
    pub key: String,
    pub value: String,
    pub managed: bool,
    pub choices: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsToggle {
    pub enabled: bool,
    pub managed: bool,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsEffort {
    pub effort: String,
    pub visible: bool,
    pub required: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct MemorySettingsView {
    pub enabled: SettingsToggle,
    pub allow_external_context: SettingsToggle,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct InstructionsView {
    pub revision: Uuid,
    pub text: String,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SaveInstructions {
    pub session: Uuid,
    pub revision: Uuid,
    pub text: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    pub revision: Uuid,
    pub account: SettingsAccountView,
    pub limits: Vec<UsageWindowView>,
    pub daily_usage: Option<Vec<DailyUsageView>>,
    pub configuration: Vec<EffectiveSettingView>,
    pub compression: Option<SettingsToggle>,
    pub network_access: Option<SettingsToggle>,
    pub efforts: Vec<SettingsEffort>,
    pub memories: Option<MemorySettingsView>,
    pub instructions_available: bool,
    pub reset_balance: Option<u32>,
    pub reset_offers: Vec<UsageResetOffer>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct UsageResetOffer {
    pub id: Option<String>,
    pub title: String,
    #[ts(type = "number | null")]
    pub expires_at: Option<i64>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RedeemUsageReset {
    pub selection: SettingsSelection,
    pub credit_id: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsSelection {
    pub session: Uuid,
    pub revision: Uuid,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteSettingsValue {
    pub selection: SettingsSelection,
    pub key: String,
    #[ts(type = "string | boolean | null")]
    pub value: serde_json::Value,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetEffortVisibility {
    pub selection: SettingsSelection,
    pub effort: String,
    pub visible: bool,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsWriteOutcome {
    pub view: SettingsView,
    pub confirmed: bool,
}
