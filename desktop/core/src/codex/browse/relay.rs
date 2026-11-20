use std::collections::HashSet;

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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayPairing {
    pub environment_id: String,
    pub pairing_code: String,
    pub manual_pairing_code: String,
    pub expires_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayClient {
    pub client_id: String,
    pub display_name: Option<String>,
    pub device_model: Option<String>,
    pub platform: Option<String>,
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

    pub async fn start_relay_pairing(
        &self,
        timeout: Duration,
    ) -> Result<RelayPairing, BrowseError> {
        self.read(
            "remoteControl/pairing/start",
            json!({"manualCode": true}),
            timeout,
        )
        .await
    }

    pub async fn relay_pairing_claimed(
        &self,
        code: &str,
        timeout: Duration,
    ) -> Result<bool, BrowseError> {
        #[derive(Deserialize)]
        struct PairingStatus {
            claimed: bool,
        }
        let response: PairingStatus = self
            .read(
                "remoteControl/pairing/status",
                json!({"pairingCode": code}),
                timeout,
            )
            .await?;
        Ok(response.claimed)
    }

    pub async fn relay_clients(
        &self,
        environment: &str,
        timeout: Duration,
    ) -> Result<Vec<RelayClient>, BrowseError> {
        let mut clients = Vec::new();
        let mut client_ids = HashSet::new();
        let mut cursors = HashSet::new();
        let mut cursor = None;
        for _ in 0..20 {
            let page: WirePage<RelayClient> = self
                .read(
                    "remoteControl/client/list",
                    json!({
                        "environmentId": environment, "cursor": cursor, "limit": PAGE_LIMIT,
                    }),
                    timeout,
                )
                .await?;
            for client in page.data {
                if client.client_id.is_empty()
                    || client.client_id.len() > 512
                    || clients.len() >= 1000
                {
                    return Err(BrowseError::RelayDevices);
                }
                if client_ids.insert(client.client_id.clone()) {
                    clients.push(client);
                }
            }
            let Some(next) = page.next_cursor else {
                return Ok(clients);
            };
            if !cursors.insert(next.clone()) {
                return Err(BrowseError::RelayDevices);
            }
            cursor = Some(next);
        }
        Err(BrowseError::RelayDevices)
    }

    pub async fn revoke_relay_client(
        &self,
        environment: &str,
        client: &str,
        timeout: Duration,
    ) -> Result<(), BrowseError> {
        self.read::<Value>(
            "remoteControl/client/revoke",
            json!({"environmentId": environment, "clientId": client}),
            timeout,
        )
        .await?;
        Ok(())
    }
}
