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
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    pub revision: Uuid,
    pub account: SettingsAccountView,
    pub limits: Vec<UsageWindowView>,
    pub daily_usage: Option<Vec<DailyUsageView>>,
    pub configuration: Vec<EffectiveSettingView>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsSelection {
    pub session: Uuid,
    pub revision: Uuid,
}
