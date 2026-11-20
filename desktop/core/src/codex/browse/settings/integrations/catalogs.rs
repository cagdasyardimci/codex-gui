use crate::codex::browse::{ComposerSkill, SkillList};
use crate::ipc::{
    HookSettings, MarketplaceSettings, PluginSettings, SettingsCatalog, SettingsCatalogKind,
    SkillSettings,
};
use crate::{
    checkout::{CheckoutIdentity, canonicalize},
    files::FileRevision,
};

use super::*;

#[derive(Clone, Default)]
pub struct IntegrationCatalogs {
    marketplaces: Option<Vec<Marketplace>>,
    hooks: Option<Vec<Hook>>,
    skills: Option<Vec<Skill>>,
}

impl IntegrationCatalogs {
    pub fn replace(&mut self, catalog: Self) {
        if catalog.marketplaces.is_some() {
            self.marketplaces = catalog.marketplaces;
        }
        if catalog.hooks.is_some() {
            self.hooks = catalog.hooks;
        }
        if catalog.skills.is_some() {
            self.skills = catalog.skills;
        }
    }

    pub fn matches(&self, kind: SettingsCatalogKind, reloaded: &Self) -> bool {
        match kind {
            SettingsCatalogKind::Plugins => {
                self.marketplaces.is_some() && self.marketplaces == reloaded.marketplaces
            }
            SettingsCatalogKind::Hooks => self.hooks.is_some() && self.hooks == reloaded.hooks,
            SettingsCatalogKind::Skills => self.skills.is_some() && self.skills == reloaded.skills,
        }
    }

    pub fn view(
        &self,
        kind: SettingsCatalogKind,
        configuration: &IntegrationConfiguration,
    ) -> SettingsCatalog {
        match kind {
            SettingsCatalogKind::Plugins => SettingsCatalog::Plugins(
                self.marketplaces
                    .iter()
                    .flatten()
                    .map(|entry| entry.view(configuration))
                    .collect(),
            ),
            SettingsCatalogKind::Hooks => SettingsCatalog::Hooks(
                self.hooks
                    .iter()
                    .flatten()
                    .map(|hook| hook.view(configuration))
                    .collect(),
            ),
            SettingsCatalogKind::Skills => SettingsCatalog::Skills(
                self.skills
                    .iter()
                    .flatten()
                    .map(|skill| SkillSettings {
                        id: skill.id.clone(),
                        name: skill.name.clone(),
                        description: skill.description.clone(),
                        enabled: skill.enabled,
                        editable: configuration.skill_editable(),
                    })
                    .collect(),
            ),
        }
    }

    pub fn for_action(action: &SettingsIntegrationAction) -> Option<SettingsCatalogKind> {
        use SettingsIntegrationAction::*;
        match action {
            UpgradeMarketplace { .. }
            | RemoveMarketplace { .. }
            | InstallPlugin { .. }
            | TogglePlugin { .. }
            | RemovePlugin { .. } => Some(SettingsCatalogKind::Plugins),
            ToggleHook { .. } | TrustHook { .. } => Some(SettingsCatalogKind::Hooks),
            ToggleSkill { .. } => Some(SettingsCatalogKind::Skills),
            _ => None,
        }
    }

    pub(super) fn operation(
        &self,
        action: &SettingsIntegrationAction,
        config: &IntegrationConfiguration,
    ) -> Option<IntegrationOperation> {
        use SettingsIntegrationAction::*;
        match action {
            ToggleSkill { id, enabled } if config.skill_editable() => {
                let skill = self.skills.as_ref()?.iter().find(|skill| skill.id == *id)?;
                Some(IntegrationOperation::request(
                    "skills/config/write",
                    json!({"path": skill.path, "enabled": enabled}),
                ))
            }
            ToggleHook { key, enabled } => {
                let hook = self.editable_hook(key, config)?;
                Some(IntegrationOperation::write(
                    format!("{}.enabled", hook.state_key()?),
                    json!(enabled),
                ))
            }
            TrustHook { key } => {
                let hook = self.editable_hook(key, config)?;
                if hook.trust_status == "trusted" || key_part(&hook.current_hash).is_none() {
                    return None;
                }
                Some(IntegrationOperation::write(
                    format!("{}.trusted_hash", hook.state_key()?),
                    json!(hook.current_hash),
                ))
            }
            _ if !config.plugins_enabled => None,
            AddMarketplace { source, reference } if !config.managed.contains("marketplaces") => {
                let mut params = json!({"source": validated_source(source)?});
                if let Some(reference) = reference {
                    params["refName"] = json!(validated_source(reference)?);
                }
                Some(IntegrationOperation::request("marketplace/add", params))
            }
            UpgradeMarketplace { name } | RemoveMarketplace { name } => {
                let entry = self.marketplace(name)?;
                if !entry.editable(config) {
                    return None;
                }
                let method = if matches!(action, UpgradeMarketplace { .. }) {
                    "marketplace/upgrade"
                } else {
                    "marketplace/remove"
                };
                Some(IntegrationOperation::request(
                    method,
                    json!({"marketplaceName": name}),
                ))
            }
            InstallPlugin { marketplace, id } => {
                let entry = self.marketplace(marketplace)?;
                let plugin = entry.plugin(id)?;
                if !plugin.view(config).can_install {
                    return None;
                }
                let mut params = json!({"pluginName": plugin.name});
                if let Some(path) = &entry.path {
                    params["marketplacePath"] = json!(path);
                } else {
                    params["remoteMarketplaceName"] = json!(entry.name);
                }
                Some(IntegrationOperation::request("plugin/install", params))
            }
            TogglePlugin {
                marketplace,
                id,
                enabled,
            } => {
                let plugin = self.marketplace(marketplace)?.plugin(id)?;
                if !plugin.view(config).can_toggle {
                    return None;
                }
                Some(IntegrationOperation::write(
                    format!("{}.enabled", plugin.state_key()?),
                    json!(enabled),
                ))
            }
            RemovePlugin { marketplace, id } => {
                let plugin = self.marketplace(marketplace)?.plugin(id)?;
                if !plugin.view(config).removable {
                    return None;
                }
                Some(IntegrationOperation::request(
                    "plugin/uninstall",
                    json!({"pluginId": id}),
                ))
            }
            _ => None,
        }
    }

    fn marketplace(&self, name: &str) -> Option<&Marketplace> {
        let mut matches = self
            .marketplaces
            .as_ref()?
            .iter()
            .filter(|entry| entry.name == name);
        let first = matches.next()?;
        matches.next().is_none().then_some(first)
    }

    fn editable_hook(&self, key: &str, config: &IntegrationConfiguration) -> Option<&Hook> {
        let mut matches = self.hooks.as_ref()?.iter().filter(|hook| hook.key == key);
        let first = matches.next()?;
        (matches.next().is_none() && first.view(config).editable).then_some(first)
    }
}

impl CodexBrowser {
    pub async fn settings_integration_catalog(
        &self,
        kind: SettingsCatalogKind,
        home: Option<&CheckoutIdentity>,
        timeout: Duration,
    ) -> Result<IntegrationCatalogs, BrowseError> {
        match kind {
            SettingsCatalogKind::Plugins => {
                #[derive(Deserialize)]
                struct Response {
                    marketplaces: Vec<Marketplace>,
                }
                let response: Response = self
                    .read("plugin/list", json!({"forceRefetch": true}), timeout)
                    .await?;
                Ok(IntegrationCatalogs {
                    marketplaces: Some(response.marketplaces),
                    ..IntegrationCatalogs::default()
                })
            }
            SettingsCatalogKind::Hooks => {
                #[derive(Deserialize)]
                struct Response {
                    data: Vec<Entry>,
                }
                #[derive(Deserialize)]
                struct Entry {
                    hooks: Vec<Hook>,
                }
                let response: Response = self.read("hooks/list", json!({}), timeout).await?;
                Ok(IntegrationCatalogs {
                    hooks: Some(
                        response
                            .data
                            .into_iter()
                            .flat_map(|entry| entry.hooks)
                            .collect(),
                    ),
                    ..IntegrationCatalogs::default()
                })
            }
            SettingsCatalogKind::Skills => {
                let Some(home) = home.filter(|home| home.revalidate().is_ok()) else {
                    return Ok(IntegrationCatalogs {
                        skills: Some(Vec::new()),
                        ..IntegrationCatalogs::default()
                    });
                };
                let response: SkillList = self
                    .read("skills/list", json!({"forceReload": true}), timeout)
                    .await?;
                home.revalidate()?;
                let mut skills = BTreeMap::new();
                for skill in response.data.into_iter().flat_map(|scope| scope.skills) {
                    if let Some(skill) = Skill::read(home, skill) {
                        skills.insert(skill.id.clone(), skill);
                    }
                }
                Ok(IntegrationCatalogs {
                    skills: Some(skills.into_values().collect()),
                    ..IntegrationCatalogs::default()
                })
            }
        }
    }
}

#[derive(Clone, Eq, PartialEq)]
struct Skill {
    id: String,
    path: PathBuf,
    name: String,
    description: String,
    enabled: bool,
}

impl Skill {
    fn read(home: &CheckoutIdentity, skill: ComposerSkill) -> Option<Self> {
        let root = home.canonical_path().join("skills");
        let path = canonicalize(std::path::Path::new(&skill.path)).ok()?;
        let relative = path.strip_prefix(root).ok()?;
        if relative.starts_with(".system") || !path.is_file() || skill.name.trim().is_empty() {
            return None;
        }
        let id = FileRevision::from_bytes(path.to_str()?.as_bytes()).digest;
        Some(Self {
            id,
            path,
            name: skill.name,
            description: skill.description,
            enabled: skill.enabled,
        })
    }
}

#[derive(Clone, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct Marketplace {
    name: String,
    path: Option<PathBuf>,
    interface: Option<MarketplaceInterface>,
    plugins: Vec<Plugin>,
}

#[derive(Clone, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct MarketplaceInterface {
    display_name: Option<String>,
}

impl Marketplace {
    fn view(&self, config: &IntegrationConfiguration) -> MarketplaceSettings {
        MarketplaceSettings {
            name: self.name.clone(),
            title: self
                .interface
                .as_ref()
                .and_then(|interface| interface.display_name.clone())
                .unwrap_or_else(|| self.name.clone()),
            editable: self.editable(config),
            plugins: self
                .plugins
                .iter()
                .map(|plugin| plugin.view(config))
                .collect(),
        }
    }

    fn editable(&self, config: &IntegrationConfiguration) -> bool {
        config.plugins_enabled
            && self.path.as_ref().is_some_and(|path| path.is_absolute())
            && !config.managed.contains("marketplaces")
    }

    fn plugin(&self, id: &str) -> Option<&Plugin> {
        let mut matches = self.plugins.iter().filter(|plugin| plugin.id == id);
        let first = matches.next()?;
        matches.next().is_none().then_some(first)
    }
}

#[derive(Clone, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct Plugin {
    id: String,
    name: String,
    interface: Option<PluginInterface>,
    installed: bool,
    enabled: bool,
    install_policy: String,
    install_policy_source: Option<String>,
    availability: Option<String>,
    must_show_installation_interstitial: Option<bool>,
}

#[derive(Clone, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct PluginInterface {
    display_name: Option<String>,
    short_description: Option<String>,
}

impl Plugin {
    fn state_key(&self) -> Option<String> {
        Some(format!("plugins.{}", key_part(&self.id)?))
    }

    fn view(&self, config: &IntegrationConfiguration) -> PluginSettings {
        let locked = self
            .state_key()
            .is_none_or(|key| config.managed.contains_subtree(&key))
            || config
                .managed
                .contains_subtree(&format!("plugins.{}", self.id));
        let allowed = config.plugins_enabled
            && !locked
            && matches!(
                self.install_policy.as_str(),
                "AVAILABLE" | "INSTALLED_BY_DEFAULT"
            )
            && self.availability.as_deref() != Some("DISABLED_BY_ADMIN");
        let managed = self.install_policy == "INSTALLED_BY_DEFAULT"
            && self.install_policy_source.as_deref() == Some("WORKSPACE_SETTING");
        PluginSettings {
            id: self.id.clone(),
            title: self
                .interface
                .as_ref()
                .and_then(|interface| interface.display_name.clone())
                .unwrap_or_else(|| self.name.clone()),
            description: self
                .interface
                .as_ref()
                .and_then(|interface| interface.short_description.clone()),
            installed: self.installed,
            enabled: self.enabled,
            can_install: !self.installed
                && allowed
                && self.must_show_installation_interstitial != Some(true),
            can_toggle: self.installed && allowed && !managed,
            removable: self.installed && allowed && !managed,
        }
    }
}

#[derive(Clone, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct Hook {
    key: String,
    event_name: String,
    source_path: PathBuf,
    enabled: bool,
    is_managed: bool,
    current_hash: String,
    trust_status: String,
}

impl Hook {
    fn state_key(&self) -> Option<String> {
        Some(format!("hooks.state.{}", key_part(&self.key)?))
    }

    fn view(&self, config: &IntegrationConfiguration) -> HookSettings {
        let locked = self
            .state_key()
            .is_none_or(|key| config.managed.contains_subtree(&key))
            || config
                .managed
                .contains_subtree(&format!("hooks.state.{}", self.key));
        HookSettings {
            key: self.key.clone(),
            event: self.event_name.clone(),
            path: self.source_path.display().to_string(),
            enabled: self.enabled,
            editable: config.writable && !self.is_managed && !config.managed_hooks_only && !locked,
            trusted: self.trust_status == "trusted",
        }
    }
}

fn validated_source(value: &str) -> Option<&str> {
    let value = value.trim();
    (!value.is_empty() && value.len() <= 4096 && !value.chars().any(char::is_control))
        .then_some(value)
}
