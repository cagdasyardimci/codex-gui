use std::{path::PathBuf, time::Duration};

use serde::{Deserialize, de::DeserializeOwned};
use serde_json::{Value, json};
use thiserror::Error;

use crate::{
    checkout::{CheckoutError, CheckoutIdentity},
    identity::{ConnectionIdentity, ThreadId},
};

use super::{AppServerClient, RequestError};

mod account;
mod history;
mod windows_sandbox;

pub use account::{BrowserLogin, LoginCancellation, LoginCompletion};
pub use windows_sandbox::{
    WindowsSandboxReadiness, WindowsSandboxSetupCompleted, WindowsSandboxSetupMode,
};

pub use history::{
    ChatRead, ChatSummary, HistoryTurn, QueueSnapshot, QueuedSubmission, ThreadActivity,
    TurnActivity, TurnCursor, TurnItemRead, TurnItems, TurnStatus,
};

const PAGE_LIMIT: u32 = 100;

#[derive(Debug, Error)]
pub enum BrowseError {
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error("select a checkout before listing project chats")]
    MissingCheckout,
    #[error("checkout path cannot be represented in the Codex protocol")]
    NonUnicodeCheckout,
    #[error("pagination cursor belongs to another read scope")]
    CursorScope,
    #[error("chat read belongs to a previous selection or connection")]
    StaleChatRead,
    #[error("app-server returned a different chat")]
    WrongThread,
    #[error("app-server returned inconsistent turn item pagination")]
    TurnItemsPagination,
    #[error("app-server returned inconsistent queue pagination")]
    QueuePagination,
    #[error("invalid response from {method}: {source}")]
    Response {
        method: &'static str,
        #[source]
        source: serde_json::Error,
    },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountSnapshot {
    pub account: Option<Account>,
    pub requires_openai_auth: bool,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Account {
    ApiKey,
    Chatgpt {
        email: Option<String>,
        #[serde(rename = "planType")]
        plan_type: String,
    },
    AmazonBedrock {
        #[serde(default, rename = "usesCodexManagedCredentials")]
        uses_codex_managed_credentials: bool,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelOption {
    pub id: String,
    pub model: String,
    pub display_name: String,
    pub description: String,
    pub hidden: bool,
    pub is_default: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadSummary {
    pub id: ThreadId,
    pub cwd: PathBuf,
    pub name: Option<String>,
    pub preview: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug)]
pub struct Page<T, C> {
    pub data: Vec<T>,
    pub next_cursor: Option<C>,
}

#[derive(Debug)]
pub struct ProjectChatCursor {
    owner: ConnectionIdentity,
    archived: bool,
    token: String,
}

#[derive(Clone)]
pub struct CodexBrowser {
    client: AppServerClient,
}

impl CodexBrowser {
    pub fn new(client: AppServerClient) -> Self {
        Self { client }
    }

    pub async fn account(&self, timeout: Duration) -> Result<AccountSnapshot, BrowseError> {
        self.read("account/read", json!({"refreshToken": false}), timeout)
            .await
    }

    pub async fn models(
        &self,
        cursor: Option<&str>,
        timeout: Duration,
    ) -> Result<Page<ModelOption, String>, BrowseError> {
        let response: WirePage<ModelOption> = self
            .read(
                "model/list",
                json!({"limit": PAGE_LIMIT, "cursor": cursor}),
                timeout,
            )
            .await?;
        Ok(response.map_cursor(|token| token))
    }

    pub async fn project_chats(
        &self,
        archived: bool,
        cursor: Option<&ProjectChatCursor>,
        timeout: Duration,
    ) -> Result<Page<ThreadSummary, ProjectChatCursor>, BrowseError> {
        let owner = self.client.identity();
        let checkout = self.checkout()?;
        let token = match cursor {
            Some(cursor) if &cursor.owner == owner && cursor.archived == archived => {
                Some(&cursor.token)
            }
            Some(_) => return Err(BrowseError::CursorScope),
            None => None,
        };
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(BrowseError::NonUnicodeCheckout)?;
        let response: WirePage<ThreadSummary> = self
            .read(
                "thread/list",
                json!({
                    "cwd": cwd,
                    "archived": archived,
                    "limit": PAGE_LIMIT,
                    "cursor": token,
                    "sourceKinds": ["appServer", "cli", "vscode"],
                }),
                timeout,
            )
            .await?;
        checkout.revalidate()?;
        for thread in &response.data {
            checkout.validate_reported(&thread.cwd)?;
        }
        Ok(response.map_cursor(|token| ProjectChatCursor {
            owner: owner.clone(),
            archived,
            token,
        }))
    }

    fn checkout(&self) -> Result<&CheckoutIdentity, BrowseError> {
        self.client
            .identity()
            .workspace
            .checkout
            .as_ref()
            .ok_or(BrowseError::MissingCheckout)
    }

    async fn read<T: DeserializeOwned>(
        &self,
        method: &'static str,
        params: Value,
        timeout: Duration,
    ) -> Result<T, BrowseError> {
        let response = self.client.request(method, params, timeout).await?;
        serde_json::from_value(response).map_err(|source| BrowseError::Response { method, source })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WirePage<T> {
    data: Vec<T>,
    next_cursor: Option<String>,
}

impl<T> WirePage<T> {
    fn map_cursor<C>(self, map: impl FnOnce(String) -> C) -> Page<T, C> {
        Page {
            data: self.data,
            next_cursor: self.next_cursor.map(map),
        }
    }
}
