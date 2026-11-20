use std::time::Duration;

use serde::Deserialize;
use serde_json::json;

use super::{BrowseError, CodexBrowser};

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum BrowserLogin {
    #[serde(rename = "chatgpt", rename_all = "camelCase")]
    Chatgpt { login_id: String, auth_url: String },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginCompletion {
    pub login_id: Option<String>,
    pub success: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LoginCancellation {
    Canceled,
    NotFound,
}

impl CodexBrowser {
    pub async fn begin_chatgpt_login(
        &self,
        timeout: Duration,
    ) -> Result<BrowserLogin, BrowseError> {
        self.read("account/login/start", json!({"type": "chatgpt"}), timeout)
            .await
    }

    pub async fn cancel_login(
        &self,
        login_id: &str,
        timeout: Duration,
    ) -> Result<LoginCancellation, BrowseError> {
        #[derive(Deserialize)]
        struct Response {
            status: LoginCancellation,
        }
        let response: Response = self
            .read(
                "account/login/cancel",
                json!({"loginId": login_id}),
                timeout,
            )
            .await?;
        Ok(response.status)
    }
}
