use std::{collections::HashSet, time::Duration};

use codex_gui_core::{
    codex::{Account, AppServerClient, BrowserLogin, CodexBrowser, LoginCompletion},
    identity::ConnectionIdentity,
    ipc::{AccountModel, AccountView},
};
use tauri::Url;
use uuid::Uuid;

use super::{Failure, RPC_TIMEOUT};

const CANCEL_TIMEOUT: Duration = Duration::from_secs(3);

pub struct AccountFlow {
    fixture: bool,
    attempt: Option<Attempt>,
}

struct Attempt {
    owner: ConnectionIdentity,
    native_id: String,
    ticket: String,
}

impl AccountFlow {
    pub fn new(fixture: bool) -> Self {
        Self {
            fixture,
            attempt: None,
        }
    }

    pub async fn start(&mut self, client: &AppServerClient) -> Result<&str, Failure> {
        if self.attempt.is_some() {
            return Err("a sign-in is already pending".into());
        }
        let browser = CodexBrowser::new(client.clone());
        let BrowserLogin::Chatgpt { login_id, auth_url } =
            browser.begin_chatgpt_login(RPC_TIMEOUT).await?;
        if login_id.is_empty() {
            return Err("Codex returned an empty sign-in identity".into());
        }
        if let Err(error) = self.open_browser(&auth_url) {
            let _ = browser.cancel_login(&login_id, CANCEL_TIMEOUT).await;
            return Err(error);
        }
        let attempt = self.attempt.insert(Attempt {
            owner: client.identity().clone(),
            native_id: login_id,
            ticket: Uuid::new_v4().to_string(),
        });
        Ok(&attempt.ticket)
    }

    pub fn can_cancel(&self, client: &AppServerClient, ticket: &str) -> bool {
        self.attempt
            .as_ref()
            .is_some_and(|attempt| attempt.owner == *client.identity() && attempt.ticket == ticket)
    }

    pub async fn retire(&mut self, client: &AppServerClient) -> Result<(), Failure> {
        if let Some(attempt) = self.attempt.take()
            && attempt.owner == *client.identity()
        {
            CodexBrowser::new(client.clone())
                .cancel_login(&attempt.native_id, CANCEL_TIMEOUT)
                .await?;
        }
        Ok(())
    }

    pub fn complete(
        &mut self,
        owner: &ConnectionIdentity,
        notification: &LoginCompletion,
    ) -> Option<bool> {
        if self.attempt.as_ref().is_some_and(|attempt| {
            &attempt.owner == owner && notification.login_id.as_deref() == Some(&attempt.native_id)
        }) {
            self.attempt = None;
            return Some(notification.success);
        }
        None
    }

    fn open_browser(&self, auth_url: &str) -> Result<(), Failure> {
        let url = authorization_url(auth_url)
            .ok_or("Codex returned an invalid ChatGPT authorization URL")?;
        if !self.fixture {
            open::that_detached(url.as_str())
                .map_err(|_| "could not open the default browser for ChatGPT sign-in")?;
        }
        Ok(())
    }
}

fn authorization_url(raw: &str) -> Option<Url> {
    let url = Url::parse(raw).ok()?;
    (url.scheme() == "https"
        && url.host_str() == Some("auth.openai.com")
        && url.port_or_known_default() == Some(443)
        && url.path() == "/oauth/authorize"
        && url.username().is_empty()
        && url.password().is_none()
        && url.fragment().is_none())
    .then_some(url)
}

pub async fn read_account(client: AppServerClient) -> Result<AccountView, Failure> {
    let browser = CodexBrowser::new(client);
    let status = browser.account(RPC_TIMEOUT).await?;
    let identity = status.account.map(|account| match account {
        Account::Chatgpt { email, .. } => email.unwrap_or_else(|| "ChatGPT".into()),
        Account::ApiKey => "OpenAI API key".into(),
        Account::AmazonBedrock { .. } => "Amazon Bedrock".into(),
        Account::Unknown => "Codex account".into(),
    });
    let permits_turns = identity.is_some() || !status.requires_openai_auth;
    let models = if permits_turns {
        let result = tokio::time::timeout(RPC_TIMEOUT, read_models(&browser)).await;
        match result.unwrap_or_else(|_| Err("model catalog refresh timed out".into())) {
            Ok(models) => models,
            Err(error) => {
                eprintln!("{error}");
                Vec::new()
            }
        }
    } else {
        Vec::new()
    };
    Ok(AccountView {
        identity,
        models,
        login_ticket: None,
        permits_turns,
    })
}

async fn read_models(browser: &CodexBrowser) -> Result<Vec<AccountModel>, Failure> {
    let mut models = Vec::new();
    let mut cursor = None;
    let mut seen = HashSet::new();
    loop {
        let page = browser.models(cursor.as_deref(), RPC_TIMEOUT).await?;
        models.extend(
            page.data
                .into_iter()
                .filter(|model| !model.hidden)
                .map(|model| AccountModel {
                    id: model.id,
                    name: model.display_name,
                    is_default: model.is_default,
                    model: model.model,
                    efforts: model.supported_reasoning_efforts,
                    default_effort: model.default_reasoning_effort,
                    service_tiers: model.service_tiers,
                }),
        );
        let Some(next) = page.next_cursor else {
            return Ok(models);
        };
        if !seen.insert(next.clone()) {
            return Err("Codex returned a repeating model cursor".into());
        }
        cursor = Some(next);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use codex_gui_core::identity::{CheckoutSessionId, ConnectionGeneration, WorkspaceIdentity};

    #[test]
    fn browser_handoff_is_limited_to_the_chatgpt_authorization_endpoint() {
        assert!(
            authorization_url("https://auth.openai.com/oauth/authorize?state=fixture").is_some()
        );
        for raw in [
            "http://auth.openai.com/oauth/authorize",
            "https://auth.openai.com:8080/oauth/authorize",
            "https://auth.openai.com/other",
            "https://auth.openai.com.example.invalid/oauth/authorize",
        ] {
            assert!(authorization_url(raw).is_none());
        }
    }

    #[test]
    fn completion_must_match_the_initiating_connection_and_login_id_once() {
        let owner = ConnectionIdentity {
            workspace: WorkspaceIdentity {
                session: CheckoutSessionId(Uuid::new_v4()),
                checkout: None,
            },
            generation: ConnectionGeneration(2),
        };
        let stale = ConnectionIdentity {
            generation: ConnectionGeneration(1),
            ..owner.clone()
        };
        let mut flow = AccountFlow::new(true);
        flow.attempt = Some(Attempt {
            owner: owner.clone(),
            native_id: "current".into(),
            ticket: "fixture".into(),
        });
        let notification = LoginCompletion {
            login_id: Some("current".into()),
            success: true,
        };
        assert_eq!(flow.complete(&stale, &notification), None);
        assert_eq!(
            flow.complete(
                &owner,
                &LoginCompletion {
                    login_id: None,
                    success: true
                }
            ),
            None
        );
        assert_eq!(flow.complete(&owner, &notification), Some(true));
        assert_eq!(flow.complete(&owner, &notification), None);
    }
}
