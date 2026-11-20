use super::*;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SettingsIntegrations {
    pub mcp_servers: Vec<McpServerSettings>,
    pub can_add_mcp: bool,
    pub can_add_marketplace: bool,
    pub browser: BrowserSettings,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct McpServerSettings {
    pub name: String,
    pub enabled: bool,
    pub editable: bool,
    pub can_authenticate: bool,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum McpTransport {
    StandardIo,
    Http,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpSettingsForm {
    pub transport: McpTransport,
    pub endpoint: String,
    pub arguments: String,
    pub environment: String,
    pub environment_variables: String,
    pub working_directory: String,
    pub headers: String,
    pub environment_headers: String,
    pub token_variable: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum BrowserPermission {
    Access,
    Downloads,
    Uploads,
    SiteTools,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
pub enum BrowserChoice {
    Allow,
    Deny,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BrowserPermissionEdit {
    pub permission: BrowserPermission,
    pub choice: Option<BrowserChoice>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct BrowserPermissionSetting {
    pub permission: BrowserPermission,
    pub choice: Option<BrowserChoice>,
    pub managed: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct BrowserSiteSettings {
    pub origin: String,
    pub permissions: Vec<BrowserPermissionSetting>,
    pub removable: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct BrowserSettings {
    pub enabled: Option<SettingsToggle>,
    pub site_tools: Option<SettingsToggle>,
    pub history: Option<BrowserChoice>,
    pub history_managed: bool,
    pub defaults: Vec<BrowserPermissionSetting>,
    pub sites: Vec<BrowserSiteSettings>,
    pub can_add_site: bool,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum SettingsCatalogKind {
    Plugins,
    Skills,
    Hooks,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct MarketplaceSettings {
    pub name: String,
    pub title: String,
    pub editable: bool,
    pub plugins: Vec<PluginSettings>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct PluginSettings {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub installed: bool,
    pub enabled: bool,
    pub can_install: bool,
    pub can_toggle: bool,
    pub removable: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct HookSettings {
    pub key: String,
    pub event: String,
    pub path: String,
    pub enabled: bool,
    pub editable: bool,
    pub trusted: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct SkillSettings {
    pub id: String,
    pub name: String,
    pub description: String,
    pub enabled: bool,
    pub editable: bool,
}

#[derive(Clone, Debug, Serialize, TS)]
#[serde(tag = "type", content = "items", rename_all = "camelCase")]
pub enum SettingsCatalog {
    Plugins(Vec<MarketplaceSettings>),
    Skills(Vec<SkillSettings>),
    Hooks(Vec<HookSettings>),
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChangeSettingsIntegration {
    pub selection: SettingsSelection,
    pub owner: Uuid,
    pub action: SettingsIntegrationAction,
}

#[derive(Debug, Deserialize, TS)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum SettingsIntegrationAction {
    SaveMcp {
        name: String,
        existing: bool,
        form: McpSettingsForm,
    },
    ToggleMcp {
        name: String,
        enabled: bool,
    },
    RemoveMcp {
        name: String,
    },
    AuthenticateMcp {
        name: String,
    },
    SetBrowserEnabled {
        enabled: bool,
    },
    SetBrowserSiteTools {
        enabled: bool,
    },
    SetBrowserHistory {
        choice: Option<BrowserChoice>,
    },
    SetBrowserDefault {
        edit: BrowserPermissionEdit,
    },
    SaveBrowserSite {
        origin: String,
        existing: bool,
        edits: Vec<BrowserPermissionEdit>,
    },
    RemoveBrowserSite {
        origin: String,
    },
    AddMarketplace {
        source: String,
        reference: Option<String>,
    },
    UpgradeMarketplace {
        name: String,
    },
    RemoveMarketplace {
        name: String,
    },
    InstallPlugin {
        marketplace: String,
        id: String,
    },
    TogglePlugin {
        marketplace: String,
        id: String,
        enabled: bool,
    },
    RemovePlugin {
        marketplace: String,
        id: String,
    },
    ToggleSkill {
        id: String,
        enabled: bool,
    },
    ToggleHook {
        key: String,
        enabled: bool,
    },
    TrustHook {
        key: String,
    },
}
