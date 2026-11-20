use super::*;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum RelayPhase {
    Disabled,
    Connecting,
    Connected,
    Errored,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RelayStatus {
    pub status: RelayPhase,
    pub installation_id: String,
    pub environment_id: Option<String>,
}

impl CodexBrowser {
    pub async fn relay_status(&self, timeout: Duration) -> Result<RelayStatus, BrowseError> {
        self.read("remoteControl/status/read", json!({}), timeout)
            .await
    }

    pub async fn set_relay_enabled(
        &self,
        enabled: bool,
        timeout: Duration,
    ) -> Result<RelayStatus, BrowseError> {
        let method = if enabled {
            "remoteControl/enable"
        } else {
            "remoteControl/disable"
        };
        self.read(method, json!({"ephemeral": true}), timeout).await
    }
}
