use std::{
    collections::{BTreeMap, HashSet},
    path::PathBuf,
    time::Duration,
};

use serde::Deserialize;
use serde_json::{Value, json};

use super::{BrowseError, CodexBrowser, WirePage};
use crate::ipc::{
    DailyUsageView, EffectiveSettingView, MemorySettingsView, SettingsToggle, UsageWindowView,
};
mod integrations;
mod usage_resets;
pub use integrations::IntegrationCatalogs;
pub use usage_resets::{ResetCandidate, UsageResetOutcome};

const COMPRESSION: &str = "local_thread_store_compression";
const COMPRESSION_KEY: &str = "features.local_thread_store_compression";
const NETWORK_KEY: &str = "sandbox_workspace_write.network_access";
const MEMORY_KEY: &str = "features.memories";
const MEMORY_EXTERNAL_KEY: &str = "memories.disable_on_external_context";
const MEMORY_GROUP: &[&str] = &[
    MEMORY_KEY,
    "memories.generate_memories",
    "memories.use_memories",
];

const CONFIGURATION_KEYS: &[(&str, Option<&str>, &[&str])] = &[
    ("model_provider", None, &[]),
    ("model", None, &[]),
    ("review_model", None, &[]),
    ("model_reasoning_effort", None, &[]),
    ("model_verbosity", None, &["", "low", "medium", "high"]),
    (
        "model_reasoning_summary",
        None,
        &["", "auto", "concise", "detailed", "none"],
    ),
    ("service_tier", None, &[]),
    (
        "approval_policy",
        Some("allowedApprovalPolicies"),
        &["untrusted", "on-request", "never"],
    ),
    (
        "approvals_reviewer",
        Some("allowedApprovalsReviewers"),
        &["user", "auto_review"],
    ),
    (
        "sandbox_mode",
        Some("allowedSandboxModes"),
        &["read-only", "workspace-write", "danger-full-access"],
    ),
    (
        "web_search",
        Some("allowedWebSearchModes"),
        &["disabled", "cached", "indexed", "live"],
    ),
    ("forced_login_method", None, &[]),
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EffectiveConfiguration {
    pub provider: Option<String>,
    pub entries: Vec<EffectiveSettingView>,
    pub version: Option<String>,
    file: Option<PathBuf>,
    pub compression: Option<SettingsToggle>,
    pub network_access: Option<SettingsToggle>,
    pub memories: Option<MemorySettingsView>,
    pub integrations: integrations::IntegrationConfiguration,
    authority: Vec<Value>,
}

impl EffectiveConfiguration {
    pub fn user_file(&self) -> Option<&std::path::Path> {
        self.file.as_deref()
    }

    pub fn accepts(&self, key: &str, value: &Value) -> bool {
        match key {
            COMPRESSION_KEY => {
                value.is_boolean()
                    && self
                        .compression
                        .as_ref()
                        .is_some_and(|setting| !setting.managed)
            }
            NETWORK_KEY => {
                value.is_boolean()
                    && self
                        .network_access
                        .as_ref()
                        .is_some_and(|setting| !setting.managed)
            }
            MEMORY_KEY => {
                value.is_boolean()
                    && self
                        .memories
                        .as_ref()
                        .is_some_and(|memory| !memory.enabled.managed)
            }
            MEMORY_EXTERNAL_KEY => {
                value.is_boolean()
                    && self.memories.as_ref().is_some_and(|memory| {
                        memory.enabled.enabled && !memory.allow_external_context.managed
                    })
            }
            _ => self
                .entries
                .iter()
                .find(|setting| setting.key == key && !setting.managed)
                .is_some_and(|setting| {
                    setting.choices.iter().any(|choice| {
                        if choice.is_empty() {
                            value.is_null()
                        } else {
                            value.as_str() == Some(choice)
                        }
                    })
                }),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurationReceipt {
    file_path: PathBuf,
    version: String,
    status: ConfigurationWriteStatus,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
enum ConfigurationWriteStatus {
    Ok,
    OkOverridden,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsRateLimits {
    pub account_id: Option<String>,
    rate_limits: RateLimitBucket,
    rate_limits_by_limit_id: Option<BTreeMap<String, RateLimitBucket>>,
    rate_limit_reset_credits: Option<usage_resets::CreditList>,
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
        let user_layer = response["layers"].as_array().and_then(|layers| {
            layers
                .iter()
                .rev()
                .find(|layer| layer["name"]["type"] == "user")
        });
        let version = user_layer.and_then(|layer| nonempty(&layer["version"]));
        let file = user_layer
            .and_then(|layer| nonempty(&layer["name"]["file"]))
            .map(PathBuf::from)
            .filter(|path| path.is_absolute());
        let custom_approval = config["approval_policy"].is_object();
        let mut authority = Vec::new();
        let mut entries = Vec::new();
        for (key, restriction, options) in CONFIGURATION_KEYS {
            let origin = &origins[*key];
            let allowed = restriction.map_or(&Value::Null, |field| &policy[field]);
            let mut choices = options
                .iter()
                .copied()
                .filter(|option| {
                    allowed.as_array().is_none_or(|values| {
                        values.iter().any(|value| value.as_str() == Some(option))
                    })
                })
                .map(str::to_owned)
                .collect::<Vec<_>>();
            let managed = managed_origin(origin)
                || allowed.as_array().is_some_and(|choices| choices.len() <= 1);
            if managed || (*key == "sandbox_mode" && custom_approval) {
                choices.clear();
            }
            let value = nonempty(&config[*key]).or_else(|| {
                (*key == "approval_policy" && custom_approval).then(|| "Custom".into())
            });
            if value.is_some() || !choices.is_empty() {
                entries.push(EffectiveSettingView {
                    key: (*key).to_owned(),
                    value: value.unwrap_or_default(),
                    managed,
                    choices,
                });
            }
            authority.push(json!([
                *key,
                origin["name"]["type"],
                origin["version"],
                allowed
            ]));
        }
        let network_access =
            (config["sandbox_mode"] == "workspace-write").then(|| SettingsToggle {
                enabled: config["sandbox_workspace_write"]["network_access"]
                    .as_bool()
                    .unwrap_or(false),
                managed: custom_approval
                    || managed_origin(&origins[NETWORK_KEY])
                    || policy["network"]["enabled"] == false,
            });
        let compression_policy = policy["featureRequirements"][COMPRESSION].as_bool();
        let features = self.settings_features(timeout).await.unwrap_or_default();
        let compression = features
            .get(COMPRESSION)
            .copied()
            .map(|effective| SettingsToggle {
                enabled: compression_policy
                    .or_else(|| config["features"][COMPRESSION].as_bool())
                    .unwrap_or(effective),
                managed: compression_policy.is_some() || managed_origin(&origins[COMPRESSION_KEY]),
            });
        let memory_policy = policy["featureRequirements"]["memories"].as_bool();
        let generate = config["memories"]["generate_memories"].as_bool();
        let use_memories = config["memories"]["use_memories"].as_bool();
        let external = config["memories"]["disable_on_external_context"].as_bool();
        let memories = features
            .get("memories")
            .copied()
            .map(|effective| MemorySettingsView {
                enabled: SettingsToggle {
                    enabled: memory_policy
                        .or_else(|| config["features"]["memories"].as_bool())
                        .unwrap_or(effective)
                        && generate != Some(false)
                        && use_memories != Some(false),
                    managed: memory_policy.is_some()
                        || MEMORY_GROUP
                            .iter()
                            .any(|key| managed_origin(&origins[*key])),
                },
                allow_external_context: SettingsToggle {
                    enabled: external != Some(true),
                    managed: managed_origin(&origins[MEMORY_EXTERNAL_KEY]),
                },
            });
        authority.push(json!([
            origins[NETWORK_KEY],
            policy["network"]["enabled"],
            origins[COMPRESSION_KEY],
            compression_policy
        ]));
        authority.push(json!([
            memory_policy,
            generate,
            use_memories,
            external,
            origins[MEMORY_EXTERNAL_KEY],
            MEMORY_GROUP
                .iter()
                .map(|key| &origins[*key])
                .collect::<Vec<_>>()
        ]));
        let integrations = integrations::IntegrationConfiguration::read(
            config,
            user_layer,
            origins,
            policy,
            &features,
            version.is_some() && file.is_some(),
        );
        Ok(EffectiveConfiguration {
            provider: nonempty(&config["model_provider"]),
            entries,
            version,
            file,
            network_access,
            compression,
            memories,
            integrations,
            authority,
        })
    }

    pub async fn write_settings_value(
        &self,
        scope: &EffectiveConfiguration,
        key: &str,
        value: Value,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        if !scope.accepts(key, &value) {
            return Err(BrowseError::SettingsScope);
        }
        let (method, request) = if key == MEMORY_KEY {
            let edits = MEMORY_GROUP
                .iter()
                .map(|key| {
                    json!({
                        "keyPath": key, "value": value, "mergeStrategy": "replace",
                    })
                })
                .collect::<Vec<_>>();
            (
                "config/batchWrite",
                json!({"edits": edits, "expectedVersion": scope.version,
                "filePath": scope.file, "reloadUserConfig": true}),
            )
        } else {
            (
                "config/value/write",
                json!({
                    "keyPath": key, "value": value, "mergeStrategy": "replace",
                    "expectedVersion": scope.version,
                    "filePath": scope.file,
                }),
            )
        };
        self.write_configuration(scope, method, request, timeout)
            .await
    }

    async fn write_configuration(
        &self,
        scope: &EffectiveConfiguration,
        method: &'static str,
        request: Value,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        let receipt: ConfigurationReceipt = self.read(method, request, timeout).await?;
        if receipt.version.is_empty()
            || !receipt.file_path.is_absolute()
            || scope.file.as_ref().is_some_and(|path| {
                path != &receipt.file_path
                    && path
                        .canonicalize()
                        .ok()
                        .zip(receipt.file_path.canonicalize().ok())
                        .is_none_or(|(a, b)| a != b)
            })
        {
            return Err(BrowseError::SettingsScope);
        }
        match receipt.status {
            ConfigurationWriteStatus::Ok | ConfigurationWriteStatus::OkOverridden => Ok(()),
        }
    }

    async fn settings_features(
        &self,
        timeout: Duration,
    ) -> Result<BTreeMap<String, bool>, BrowseError> {
        #[derive(Deserialize)]
        struct Feature {
            name: String,
            enabled: bool,
        }
        let mut cursor = None;
        let mut seen = HashSet::new();
        let mut features = BTreeMap::new();
        for _ in 0..10 {
            let page: WirePage<Feature> = self
                .read(
                    "experimentalFeature/list",
                    json!({
                        "cursor": cursor, "limit": super::PAGE_LIMIT,
                    }),
                    timeout,
                )
                .await?;
            features.extend(
                page.data
                    .into_iter()
                    .filter(|feature| {
                        matches!(
                            feature.name.as_str(),
                            COMPRESSION
                                | "memories"
                                | "browser_use"
                                | "browser_use_full_cdp_access"
                        )
                    })
                    .map(|feature| (feature.name, feature.enabled)),
            );
            if features.len() == 4 {
                break;
            }
            match page.next_cursor {
                Some(next) if seen.insert(next.clone()) => cursor = Some(next),
                _ => break,
            }
        }
        Ok(features)
    }

    pub async fn reset_settings_memories(&self, timeout: Duration) -> Result<(), BrowseError> {
        self.read::<BTreeMap<String, Value>>("memory/reset", json!({}), timeout)
            .await?;
        Ok(())
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

fn managed_origin(origin: &Value) -> bool {
    matches!(
        origin["name"]["type"].as_str(),
        Some("mdm" | "system" | "enterpriseManaged")
    )
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
