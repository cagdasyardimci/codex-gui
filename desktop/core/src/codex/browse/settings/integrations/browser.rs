use crate::ipc::{
    BrowserChoice, BrowserPermission, BrowserPermissionEdit, BrowserPermissionSetting,
    BrowserSettings, BrowserSiteSettings,
};

use super::*;

const DEFAULTS: &str = "browser_use.default_origin_policy";
const ORIGINS: &str = "browser_use.origins";
const HISTORY: &str = "browser_use.allow_history_access";
const PERMISSIONS: [BrowserPermission; 4] = [
    BrowserPermission::Access,
    BrowserPermission::Downloads,
    BrowserPermission::Uploads,
    BrowserPermission::SiteTools,
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct BrowserConfiguration {
    enabled: Option<SettingsToggle>,
    site_tools: Option<SettingsToggle>,
    history: Option<BrowserChoice>,
    history_managed: bool,
    defaults: Map<String, Value>,
    sites: Map<String, Value>,
    user_sites: Map<String, Value>,
    requirements: Value,
    writable: bool,
}

impl BrowserConfiguration {
    pub(super) fn read(
        config: &Value,
        user: &Value,
        requirements: &Value,
        features: &BTreeMap<String, bool>,
        managed: &ManagedOrigins,
        writable: bool,
    ) -> Self {
        let policy = &requirements["browserUse"];
        let allowed = requirements["allowBrowserAndComputerUse"].as_bool() != Some(false);
        let writable = writable && allowed;
        let feature = |name: &str| {
            let fixed = if allowed {
                requirements["featureRequirements"][name].as_bool()
            } else {
                Some(false)
            };
            let resolution = features.get(name);
            let enabled = fixed.or(resolution.copied())?;
            Some(SettingsToggle {
                enabled,
                managed: !writable
                    || fixed.is_some()
                    || managed.contains(&format!("features.{name}")),
            })
        };
        let required_history = policy["allowHistoryAccess"].as_bool();
        Self {
            enabled: feature("browser_use"),
            site_tools: feature("browser_use_full_cdp_access"),
            history: required_history
                .or(config["browser_use"]["allow_history_access"].as_bool())
                .map(|allow| {
                    if allow {
                        BrowserChoice::Allow
                    } else {
                        BrowserChoice::Deny
                    }
                }),
            history_managed: !writable || required_history.is_some() || managed.contains(HISTORY),
            defaults: object(&config["browser_use"]["default_origin_policy"]),
            sites: object(&config["browser_use"]["origins"]),
            user_sites: object(&user["browser_use"]["origins"]),
            requirements: policy.clone(),
            writable,
        }
    }

    pub(super) fn view(&self, managed: &ManagedOrigins) -> BrowserSettings {
        let required_sites = object(&self.requirements["origins"]);
        let origins = self
            .sites
            .keys()
            .chain(required_sites.keys())
            .collect::<std::collections::BTreeSet<_>>();
        BrowserSettings {
            enabled: self.enabled.clone(),
            site_tools: self.site_tools.clone(),
            history: self.history,
            history_managed: self.history_managed,
            defaults: PERMISSIONS
                .iter()
                .map(|permission| self.default_setting(*permission, managed))
                .collect(),
            sites: origins
                .into_iter()
                .map(|origin| BrowserSiteSettings {
                    origin: origin.clone(),
                    permissions: PERMISSIONS
                        .iter()
                        .map(|permission| self.site_setting(origin, *permission, managed))
                        .collect(),
                    removable: self.removable(origin, managed),
                })
                .collect(),
            can_add_site: self.writable && !managed.contains(ORIGINS),
        }
    }

    fn default_setting(
        &self,
        permission: BrowserPermission,
        managed: &ManagedOrigins,
    ) -> BrowserPermissionSetting {
        let key = config_key(permission);
        let fixed =
            read_choice(&self.requirements["defaultOriginPolicy"][requirement_key(permission)]);
        BrowserPermissionSetting {
            permission,
            choice: fixed.or_else(|| self.defaults.get(key).and_then(read_choice)),
            managed: !self.writable
                || fixed.is_some()
                || managed.contains(&format!("{DEFAULTS}.{key}")),
        }
    }

    fn site_setting(
        &self,
        origin: &str,
        permission: BrowserPermission,
        managed: &ManagedOrigins,
    ) -> BrowserPermissionSetting {
        let key = config_key(permission);
        let fixed = self
            .site_requirement(origin)
            .and_then(|policy| read_choice(&policy[requirement_key(permission)]));
        let locked = key_part(origin)
            .is_none_or(|part| managed.contains(&format!("{ORIGINS}.{part}.{key}")))
            || managed.contains(&format!("{ORIGINS}.{origin}.{key}"));
        BrowserPermissionSetting {
            permission,
            choice: fixed.or_else(|| {
                self.sites
                    .get(origin)
                    .and_then(|policy| read_choice(&policy[key]))
            }),
            managed: !self.writable
                || fixed.is_some()
                || locked
                || self.sites.contains_key(origin) && !self.user_sites.contains_key(origin),
        }
    }

    fn site_requirement(&self, origin: &str) -> Option<&Value> {
        let requirements = self.requirements["origins"].as_object()?;
        requirements.get(origin).or_else(|| {
            let normalized = normalize_origin(origin)?;
            requirements.iter().find_map(|(key, policy)| {
                (normalize_origin(key).as_deref() == Some(&normalized)).then_some(policy)
            })
        })
    }

    fn removable(&self, origin: &str, managed: &ManagedOrigins) -> bool {
        self.writable
            && self.user_sites.contains_key(origin)
            && key_part(origin)
                .is_some_and(|part| !managed.contains_subtree(&format!("{ORIGINS}.{part}")))
            && !managed.contains_subtree(&format!("{ORIGINS}.{origin}"))
            && self.site_requirement(origin).is_none()
    }

    pub(super) fn operation(
        &self,
        action: &SettingsIntegrationAction,
        managed: &ManagedOrigins,
    ) -> Option<IntegrationOperation> {
        use SettingsIntegrationAction::*;
        if !self.writable {
            return None;
        }
        let (key, value) = match action {
            SetBrowserEnabled { enabled }
                if self
                    .enabled
                    .as_ref()
                    .is_some_and(|setting| !setting.managed) =>
            {
                ("features.browser_use".into(), json!(enabled))
            }
            SetBrowserSiteTools { enabled }
                if self
                    .site_tools
                    .as_ref()
                    .is_some_and(|setting| !setting.managed) =>
            {
                (
                    "features.browser_use_full_cdp_access".into(),
                    json!(enabled),
                )
            }
            SetBrowserHistory { choice } if !self.history_managed => (
                HISTORY.into(),
                json!(choice.map(|choice| choice == BrowserChoice::Allow)),
            ),
            SetBrowserDefault { edit }
                if !self.default_setting(edit.permission, managed).managed =>
            {
                (
                    format!("{DEFAULTS}.{}", config_key(edit.permission)),
                    json!(edit.choice),
                )
            }
            SaveBrowserSite {
                origin,
                existing,
                edits,
            } => {
                let key = if *existing {
                    self.user_sites.get(origin)?;
                    origin.clone()
                } else {
                    let proposed = normalize_origin(origin)?;
                    if self
                        .sites
                        .keys()
                        .any(|site| normalize_origin(site).as_deref() == Some(&proposed))
                    {
                        return None;
                    }
                    proposed
                };
                let sites = self.updated_sites(key, edits, managed)?;
                (ORIGINS.into(), Value::Object(sites))
            }
            RemoveBrowserSite { origin } if self.removable(origin, managed) => {
                let mut sites = self.user_sites.clone();
                sites.remove(origin)?;
                (ORIGINS.into(), Value::Object(sites))
            }
            _ => return None,
        };
        Some(IntegrationOperation::write(key, value))
    }

    fn updated_sites(
        &self,
        origin: String,
        edits: &[BrowserPermissionEdit],
        managed: &ManagedOrigins,
    ) -> Option<Map<String, Value>> {
        if edits.is_empty() || edits.len() > PERMISSIONS.len() || managed.contains(ORIGINS) {
            return None;
        }
        let mut sites = self.user_sites.clone();
        let mut site = sites.get(&origin).map(object).unwrap_or_default();
        let mut keys = HashSet::new();
        for edit in edits {
            let key = config_key(edit.permission);
            if !keys.insert(key) || self.site_setting(&origin, edit.permission, managed).managed {
                return None;
            }
            if let Some(choice) = edit.choice {
                site.insert(key.into(), json!(choice));
            } else {
                site.remove(key);
            }
        }
        if site.is_empty() {
            sites.remove(&origin);
        } else {
            sites.insert(origin, Value::Object(site));
        }
        Some(sites)
    }
}

fn normalize_origin(input: &str) -> Option<String> {
    let input = input.trim();
    if input.len() > 2048
        || input
            .chars()
            .any(|ch| ch.is_whitespace() || ch.is_control())
        || input.contains('\\')
    {
        return None;
    }
    let (_, authority) = input.split_once("://")?;
    let authority = authority.strip_suffix('/').unwrap_or(authority);
    if authority.is_empty() || authority.contains(['/', '?', '#', '@']) {
        return None;
    }
    let url = web_url(input)?;
    // Keep an explicitly entered port, including an explicit default port.
    let port = authority
        .rsplit_once(':')
        .filter(|(_, port)| port.bytes().all(|byte| byte.is_ascii_digit()));
    let host = url.host_str()?;
    let mut origin = format!("{}://{host}", url.scheme());
    if let Some((_, port)) = port {
        let port = port.parse::<u16>().ok()?;
        origin.push_str(&format!(":{port}"));
    }
    Some(origin)
}

fn read_choice(value: &Value) -> Option<BrowserChoice> {
    match value.as_str()? {
        "allow" => Some(BrowserChoice::Allow),
        "deny" => Some(BrowserChoice::Deny),
        _ => None,
    }
}

fn config_key(permission: BrowserPermission) -> &'static str {
    match permission {
        BrowserPermission::Access => "access",
        BrowserPermission::Downloads => "downloads",
        BrowserPermission::Uploads => "uploads",
        BrowserPermission::SiteTools => "full_cdp_access",
    }
}

fn requirement_key(permission: BrowserPermission) -> &'static str {
    if permission == BrowserPermission::SiteTools {
        "fullCdpAccess"
    } else {
        config_key(permission)
    }
}
