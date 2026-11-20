use serde_json::Map;
use url::Url;

use crate::ipc::{McpSettingsForm, SettingsIntegrationAction, SettingsIntegrations};

use super::*;

mod browser;
mod catalogs;
mod mcp;
pub use catalogs::IntegrationCatalogs;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct IntegrationConfiguration {
    mcp: mcp::McpConfiguration,
    browser: browser::BrowserConfiguration,
    managed: ManagedOrigins,
    writable: bool,
    plugins_enabled: bool,
    managed_hooks_only: bool,
}

impl IntegrationConfiguration {
    pub(super) fn read(
        config: &Value,
        user_layer: Option<&Value>,
        origins: &Value,
        requirements: &Value,
        features: &BTreeMap<String, bool>,
        writable: bool,
    ) -> Self {
        let user = user_layer.map_or(&Value::Null, |layer| &layer["config"]);
        let managed = ManagedOrigins::read(origins);
        Self {
            mcp: mcp::McpConfiguration::read(config, user, &managed, writable),
            browser: browser::BrowserConfiguration::read(
                config,
                user,
                requirements,
                features,
                &managed,
                writable,
            ),
            managed,
            writable,
            plugins_enabled: requirements["featureRequirements"]["plugins"].as_bool()
                != Some(false)
                && config["features"]["plugins"].as_bool() != Some(false),
            managed_hooks_only: requirements["allowManagedHooksOnly"].as_bool() == Some(true),
        }
    }

    pub fn view(&self) -> SettingsIntegrations {
        SettingsIntegrations {
            mcp_servers: self.mcp.rows(&self.managed),
            can_add_mcp: self.mcp.writable(),
            can_add_marketplace: self.writable
                && self.plugins_enabled
                && !self.managed.contains("marketplaces"),
            browser: self.browser.view(&self.managed),
        }
    }

    pub fn mcp_form(&self, name: &str) -> Option<McpSettingsForm> {
        self.mcp.form(name, &self.managed)
    }

    fn skill_editable(&self) -> bool {
        self.writable && !self.managed.contains_subtree("skills.config")
    }

    pub fn operation(
        &self,
        action: &SettingsIntegrationAction,
        catalogs: &IntegrationCatalogs,
    ) -> Option<IntegrationOperation> {
        if !self.writable {
            return None;
        }
        match action {
            SettingsIntegrationAction::SaveMcp { .. }
            | SettingsIntegrationAction::RemoveMcp { .. }
            | SettingsIntegrationAction::ToggleMcp { .. }
            | SettingsIntegrationAction::AuthenticateMcp { .. } => {
                self.mcp.operation(action, &self.managed)
            }
            SettingsIntegrationAction::SetBrowserEnabled { .. }
            | SettingsIntegrationAction::SetBrowserSiteTools { .. }
            | SettingsIntegrationAction::SetBrowserHistory { .. }
            | SettingsIntegrationAction::SetBrowserDefault { .. }
            | SettingsIntegrationAction::SaveBrowserSite { .. }
            | SettingsIntegrationAction::RemoveBrowserSite { .. } => {
                self.browser.operation(action, &self.managed)
            }
            _ => catalogs.operation(action, self),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ManagedOrigins {
    keys: Vec<String>,
}

impl ManagedOrigins {
    fn read(origins: &Value) -> Self {
        Self {
            keys: origins
                .as_object()
                .into_iter()
                .flatten()
                .filter(|(_, origin)| managed_origin(origin))
                .map(|(key, _)| key.clone())
                .collect(),
        }
    }

    fn contains(&self, key: &str) -> bool {
        self.keys.iter().any(|managed| {
            managed == key
                || key
                    .strip_prefix(managed)
                    .is_some_and(|remainder| remainder.starts_with('.'))
        })
    }

    fn contains_subtree(&self, key: &str) -> bool {
        self.contains(key)
            || self.keys.iter().any(|managed| {
                managed
                    .strip_prefix(key)
                    .is_some_and(|remainder| remainder.starts_with('.'))
            })
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct IntegrationOperation(Operation);

#[derive(Debug, Eq, PartialEq)]
enum Operation {
    Configuration {
        key: String,
        value: Value,
        reload_mcp: bool,
    },
    Request {
        method: &'static str,
        params: Value,
    },
    OAuth {
        server: String,
    },
}

impl IntegrationOperation {
    fn write(key: impl Into<String>, value: Value) -> Self {
        Self(Operation::Configuration {
            key: key.into(),
            value,
            reload_mcp: false,
        })
    }

    fn request(method: &'static str, params: Value) -> Self {
        Self(Operation::Request { method, params })
    }

    pub fn changes_configuration(&self) -> bool {
        matches!(self.0, Operation::Configuration { .. })
    }
}

impl CodexBrowser {
    pub async fn change_settings_integration(
        &self,
        configuration: &EffectiveConfiguration,
        operation: IntegrationOperation,
        timeout: Duration,
    ) -> Result<Option<Url>, BrowseError> {
        match operation.0 {
            Operation::Configuration {
                key,
                value,
                reload_mcp,
            } => {
                let request = json!({
                    "keyPath": key, "value": value, "mergeStrategy": "replace",
                    "expectedVersion": configuration.version, "filePath": configuration.file,
                });
                self.write_configuration(configuration, "config/value/write", request, timeout)
                    .await?;
                if reload_mcp {
                    self.read::<BTreeMap<String, Value>>(
                        "config/mcpServer/reload",
                        Value::Null,
                        timeout,
                    )
                    .await?;
                }
                Ok(None)
            }
            Operation::Request { method, mut params } => {
                if method == "plugin/install" {
                    params["installAttemptId"] = json!(uuid::Uuid::new_v4());
                }
                self.read::<BTreeMap<String, Value>>(method, params, timeout)
                    .await?;
                Ok(None)
            }
            Operation::OAuth { server } => {
                #[derive(Deserialize)]
                #[serde(rename_all = "camelCase")]
                struct Receipt {
                    authorization_url: String,
                }
                let receipt: Receipt = self
                    .read("mcpServer/oauth/login", json!({"name": server}), timeout)
                    .await?;
                web_url(&receipt.authorization_url)
                    .map(Some)
                    .ok_or(BrowseError::SettingsScope)
            }
        }
    }
}

fn object(value: &Value) -> Map<String, Value> {
    value.as_object().cloned().unwrap_or_default()
}

fn key_part(value: &str) -> Option<String> {
    if value.is_empty() || value.len() > 4096 || value.chars().any(char::is_control) {
        return None;
    }
    serde_json::to_string(value).ok()
}

fn web_url(raw: &str) -> Option<Url> {
    let url = Url::parse(raw).ok()?;
    (matches!(url.scheme(), "http" | "https")
        && url.has_host()
        && url.username().is_empty()
        && url.password().is_none())
    .then_some(url)
}
