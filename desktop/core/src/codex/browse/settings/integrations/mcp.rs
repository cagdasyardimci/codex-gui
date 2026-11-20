use crate::ipc::{McpServerSettings, McpSettingsForm, McpTransport};

use super::*;

const TABLE: &str = "mcp_servers";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct McpConfiguration {
    effective: Map<String, Value>,
    user: Map<String, Value>,
    writable: bool,
}

impl McpConfiguration {
    pub(super) fn read(
        config: &Value,
        user: &Value,
        managed: &ManagedOrigins,
        writable: bool,
    ) -> Self {
        Self {
            effective: object(&config[TABLE]),
            user: object(&user[TABLE]),
            writable: writable && !managed.contains(TABLE),
        }
    }

    pub(super) fn writable(&self) -> bool {
        self.writable
    }

    pub(super) fn rows(&self, managed: &ManagedOrigins) -> Vec<McpServerSettings> {
        self.effective
            .iter()
            .filter_map(|(name, value)| {
                let entry = value.as_object()?;
                Some(McpServerSettings {
                    name: name.clone(),
                    enabled: enabled(entry),
                    editable: self.can_edit(name, managed),
                    can_authenticate: can_authenticate(entry),
                })
            })
            .collect()
    }

    pub(super) fn form(&self, name: &str, managed: &ManagedOrigins) -> Option<McpSettingsForm> {
        if !self.can_edit(name, managed) {
            return None;
        }
        let config = self.user.get(name)?;
        let (transport, endpoint) = match config["url"].as_str() {
            Some(url) => (McpTransport::Http, url),
            None => (
                McpTransport::StandardIo,
                config["command"].as_str().unwrap_or_default(),
            ),
        };
        Some(McpSettingsForm {
            transport,
            endpoint: endpoint.to_owned(),
            arguments: text_array(&config["args"]),
            environment: text_pairs(&config["env"]),
            environment_variables: text_array(&config["env_vars"]),
            working_directory: config["cwd"].as_str().unwrap_or_default().to_owned(),
            headers: text_pairs(&config["http_headers"]),
            environment_headers: text_pairs(&config["env_http_headers"]),
            token_variable: config["bearer_token_env_var"]
                .as_str()
                .unwrap_or_default()
                .to_owned(),
        })
    }

    fn can_edit(&self, name: &str, managed: &ManagedOrigins) -> bool {
        self.writable && self.user.contains_key(name) && !locked(name, managed)
    }

    pub(super) fn operation(
        &self,
        action: &SettingsIntegrationAction,
        managed: &ManagedOrigins,
    ) -> Option<IntegrationOperation> {
        use SettingsIntegrationAction::*;
        let mut servers = self.user.clone();
        match action {
            SaveMcp {
                name,
                existing,
                form,
            } => {
                let name = if *existing {
                    name.as_str()
                } else {
                    name.trim()
                };
                if !self.writable
                    || !valid_name(name)
                    || locked(name, managed)
                    || (*existing && !self.user.contains_key(name))
                    || (!existing
                        && (self.effective.contains_key(name) || self.user.contains_key(name)))
                {
                    return None;
                }
                let previous = self.user.get(name).map(object).unwrap_or_default();
                servers.insert(
                    name.to_owned(),
                    Value::Object(updated_form(previous, form)?),
                );
            }
            ToggleMcp { name, enabled } if self.can_edit(name, managed) => {
                servers
                    .get_mut(name)?
                    .as_object_mut()?
                    .insert("enabled".into(), json!(enabled));
            }
            RemoveMcp { name } if self.can_edit(name, managed) => {
                servers.remove(name)?;
            }
            AuthenticateMcp { name }
                if self
                    .effective
                    .get(name)
                    .and_then(Value::as_object)
                    .is_some_and(can_authenticate) =>
            {
                return Some(IntegrationOperation(Operation::OAuth {
                    server: name.clone(),
                }));
            }
            _ => return None,
        }
        Some(IntegrationOperation(Operation::Configuration {
            key: TABLE.into(),
            value: Value::Object(servers),
            reload_mcp: true,
        }))
    }
}

fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 128 && !name.chars().any(char::is_control)
}

fn locked(name: &str, managed: &ManagedOrigins) -> bool {
    key_part(name).is_none_or(|part| managed.contains_subtree(&format!("{TABLE}.{part}")))
        || managed.contains_subtree(&format!("{TABLE}.{name}"))
}

fn enabled(config: &Map<String, Value>) -> bool {
    config
        .get("enabled")
        .and_then(Value::as_bool)
        .unwrap_or(true)
}

fn can_authenticate(config: &Map<String, Value>) -> bool {
    enabled(config)
        && config
            .get("url")
            .and_then(Value::as_str)
            .and_then(web_url)
            .is_some()
}

fn updated_form(
    mut config: Map<String, Value>,
    form: &McpSettingsForm,
) -> Option<Map<String, Value>> {
    let endpoint = form.endpoint.trim();
    if endpoint.is_empty() || endpoint.len() > 4096 || endpoint.chars().any(char::is_control) {
        return None;
    }
    match form.transport {
        McpTransport::StandardIo => {
            for key in [
                "url",
                "auth",
                "oauth",
                "scopes",
                "oauth_resource",
                "http_headers",
                "env_http_headers",
                "bearer_token_env_var",
            ] {
                config.remove(key);
            }
            config.insert("command".into(), json!(endpoint));
            replace(&mut config, "args", lines(&form.arguments)?);
            replace(&mut config, "env", pairs(&form.environment)?);
            replace(&mut config, "env_vars", lines(&form.environment_variables)?);
            replace(&mut config, "cwd", text(&form.working_directory)?);
        }
        McpTransport::Http => {
            let url = web_url(endpoint)?;
            if url.fragment().is_some() {
                return None;
            }
            for key in ["command", "args", "env", "env_vars", "cwd"] {
                config.remove(key);
            }
            config.insert("url".into(), json!(endpoint));
            replace(&mut config, "http_headers", pairs(&form.headers)?);
            replace(
                &mut config,
                "env_http_headers",
                pairs(&form.environment_headers)?,
            );
            replace(
                &mut config,
                "bearer_token_env_var",
                text(&form.token_variable)?,
            );
        }
    }
    Some(config)
}

fn replace(config: &mut Map<String, Value>, key: &str, value: Value) {
    if value.is_null() {
        config.remove(key);
    } else {
        config.insert(key.to_owned(), value);
    }
}

fn lines(input: &str) -> Option<Value> {
    if input.len() > 65_536 || input.contains('\0') {
        return None;
    }
    let lines = input
        .lines()
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    Some(if lines.is_empty() {
        Value::Null
    } else {
        json!(lines)
    })
}

fn pairs(input: &str) -> Option<Value> {
    if input.len() > 65_536 || input.contains('\0') {
        return None;
    }
    let mut pairs = BTreeMap::new();
    for line in input.lines().filter(|line| !line.is_empty()) {
        let (key, value) = line.split_once('=')?;
        let key = key.trim();
        if key.is_empty() || key.chars().any(char::is_control) || pairs.insert(key, value).is_some()
        {
            return None;
        }
    }
    Some(if pairs.is_empty() {
        Value::Null
    } else {
        json!(pairs)
    })
}

fn text(input: &str) -> Option<Value> {
    let input = input.trim();
    if input.len() > 4096 || input.chars().any(char::is_control) {
        return None;
    }
    Some(if input.is_empty() {
        Value::Null
    } else {
        json!(input)
    })
}

fn text_array(value: &Value) -> String {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .collect::<Vec<_>>()
        .join("\n")
}

fn text_pairs(value: &Value) -> String {
    value
        .as_object()
        .into_iter()
        .flatten()
        .filter_map(|(key, value)| value.as_str().map(|value| format!("{key}={value}")))
        .collect::<Vec<_>>()
        .join("\n")
}
