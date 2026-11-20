use std::{collections::BTreeMap, time::Duration};

use serde::Deserialize;
use serde_json::{Value, json};

use super::{BrowseError, CodexBrowser};
use crate::ipc::{DailyUsageView, EffectiveSettingView, UsageWindowView};

const CONFIGURATION_KEYS: &[(&str, Option<&str>)] = &[
    ("model_provider", None),
    ("model", None),
    ("review_model", None),
    ("model_reasoning_effort", None),
    ("model_verbosity", None),
    ("service_tier", None),
    ("approval_policy", Some("allowedApprovalPolicies")),
    ("approvals_reviewer", Some("allowedApprovalsReviewers")),
    ("sandbox_mode", Some("allowedSandboxModes")),
    ("web_search", Some("allowedWebSearchModes")),
    ("forced_login_method", None),
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EffectiveConfiguration {
    pub provider: Option<String>,
    pub entries: Vec<EffectiveSettingView>,
    pub version: Option<String>,
    authority: Vec<Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsRateLimits {
    pub account_id: Option<String>,
    rate_limits: RateLimitBucket,
    rate_limits_by_limit_id: Option<BTreeMap<String, RateLimitBucket>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitBucket {
    limit_name: Option<String>,
    plan_type: Option<String>,
    primary: Option<RateLimitWindow>,
    secondary: Option<RateLimitWindow>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitWindow {
    used_percent: Option<f64>,
    window_duration_mins: Option<u32>,
    resets_at: Option<i64>,
}

impl SettingsRateLimits {
    pub fn plan(&self) -> Option<String> {
        self.rate_limits.plan_type.clone().or_else(|| {
            self.rate_limits_by_limit_id
                .as_ref()?
                .get("codex")?
                .plan_type
                .clone()
        })
    }

    pub fn windows(&self) -> Vec<UsageWindowView> {
        if let Some(buckets) = &self.rate_limits_by_limit_id
            && !buckets.is_empty()
        {
            return buckets
                .iter()
                .flat_map(|(name, bucket)| bucket.windows(name))
                .collect();
        }
        self.rate_limits.windows("codex")
    }
}

impl RateLimitBucket {
    fn windows(&self, key: &str) -> Vec<UsageWindowView> {
        let name = self
            .limit_name
            .as_deref()
            .filter(|name| !name.trim().is_empty())
            .unwrap_or(if key == "codex" { "Codex" } else { key });
        [self.primary.as_ref(), self.secondary.as_ref()]
            .into_iter()
            .flatten()
            .map(|window| UsageWindowView {
                name: name.to_owned(),
                minutes: window.window_duration_mins,
                remaining_percent: window
                    .used_percent
                    .filter(|used| used.is_finite())
                    .map(|used| (100.0 - used).clamp(0.0, 100.0)),
                resets_at: window.resets_at,
            })
            .collect()
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DailyUsageBucket {
    start_date: String,
    tokens: Option<u64>,
}

impl CodexBrowser {
    pub async fn settings_configuration(
        &self,
        timeout: Duration,
    ) -> Result<EffectiveConfiguration, BrowseError> {
        let (response, requirements) = tokio::try_join!(
            self.read::<Value>("config/read", json!({"includeLayers": true}), timeout),
            self.read::<Value>("configRequirements/read", json!({}), timeout),
        )?;
        let config = &response["config"];
        let origins = &response["origins"];
        let policy = &requirements["requirements"];
        let version = response["layers"]
            .as_array()
            .and_then(|layers| {
                layers
                    .iter()
                    .rev()
                    .find(|layer| layer["name"]["type"] == "user")
            })
            .and_then(|layer| nonempty(&layer["version"]));
        let mut authority = Vec::new();
        let mut entries = Vec::new();
        for (key, restriction) in CONFIGURATION_KEYS {
            let origin = &origins[*key];
            let allowed = restriction.map_or(&Value::Null, |field| &policy[field]);
            if let Some(value) = nonempty(&config[*key]) {
                entries.push(EffectiveSettingView {
                    key: (*key).to_owned(),
                    value,
                    managed: matches!(
                        origin["name"]["type"].as_str(),
                        Some("mdm" | "system" | "enterpriseManaged")
                    ) || allowed.as_array().is_some_and(|choices| choices.len() <= 1),
                });
            }
            authority.push(json!([
                *key,
                origin["name"]["type"],
                origin["version"],
                allowed
            ]));
        }
        Ok(EffectiveConfiguration {
            provider: nonempty(&config["model_provider"]),
            entries,
            version,
            authority,
        })
    }

    pub async fn settings_rate_limits(
        &self,
        timeout: Duration,
    ) -> Result<SettingsRateLimits, BrowseError> {
        self.read("account/rateLimits/read", json!({}), timeout)
            .await
    }

    pub async fn settings_daily_usage(
        &self,
        timeout: Duration,
    ) -> Result<Option<Vec<DailyUsageView>>, BrowseError> {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Response {
            daily_usage_buckets: Option<Vec<DailyUsageBucket>>,
        }
        let response: Response = self.read("account/usage/read", json!({}), timeout).await?;
        Ok(response.daily_usage_buckets.map(|buckets| {
            let ordered: BTreeMap<_, _> = buckets
                .into_iter()
                .filter_map(|entry| {
                    if !date_key(&entry.start_date) {
                        return None;
                    }
                    Some((entry.start_date, entry.tokens?))
                })
                .collect();
            ordered
                .into_iter()
                .rev()
                .take(31)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .map(|(date, tokens)| DailyUsageView { date, tokens })
                .collect()
        }))
    }

    pub async fn settings_logout(&self, timeout: Duration) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>("account/logout", json!({}), timeout)
            .await?;
        Ok(())
    }
}

fn nonempty(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

fn date_key(date: &str) -> bool {
    date.len() == 10
        && date.bytes().enumerate().all(|(index, byte)| {
            if matches!(index, 4 | 7) {
                byte == b'-'
            } else {
                byte.is_ascii_digit()
            }
        })
}
