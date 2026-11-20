use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::sync::watch;

use super::{BrowseError, CodexBrowser};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum WindowsSandboxReadiness {
    NotConfigured,
    UpdateRequired,
    Ready,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}

#[derive(Debug, Deserialize)]
pub struct WindowsSandboxSetupCompleted {
    pub mode: WindowsSandboxSetupMode,
    pub success: bool,
    pub error: Option<String>,
}

impl CodexBrowser {
    pub async fn windows_sandbox_readiness(
        &self,
        timeout: Duration,
    ) -> Result<WindowsSandboxReadiness, BrowseError> {
        #[derive(Deserialize)]
        struct Reply {
            status: WindowsSandboxReadiness,
        }
        let reply: Reply = self
            .read("windowsSandbox/readiness", Value::Null, timeout)
            .await?;
        Ok(reply.status)
    }

    pub async fn start_windows_sandbox_setup(
        &self,
        mode: WindowsSandboxSetupMode,
        timeout: Duration,
    ) -> Result<bool, BrowseError> {
        #[derive(Deserialize)]
        struct Reply {
            started: bool,
        }
        let checkout = self.checkout()?.clone();
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(BrowseError::NonUnicodeCheckout)?;
        let (_stop, stopped) = watch::channel(false);
        let method = "windowsSandbox/setupStart";
        let response = self
            .client
            .request_scoped(
                method,
                json!({"mode": mode, "cwd": cwd}),
                timeout,
                checkout.clone(),
                stopped,
            )
            .await?;
        let reply: Reply = serde_json::from_value(response)
            .map_err(|source| BrowseError::Response { method, source })?;
        Ok(reply.started)
    }
}
