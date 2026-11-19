use std::time::Duration;

use serde::{Deserialize, de::DeserializeOwned};
use serde_json::{Value, json};

use crate::identity::{ConnectionIdentity, ThreadId, TurnId};

use super::{BrowseError, CodexBrowser, Page, ThreadSummary, WirePage};

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ThreadActivity {
    NotLoaded,
    Idle,
    SystemError,
    Active {
        #[serde(rename = "activeFlags")]
        flags: Vec<String>,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Deserialize)]
pub struct ChatSummary {
    #[serde(flatten)]
    pub thread: ThreadSummary,
    #[serde(rename = "status")]
    pub activity: ThreadActivity,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Deserialize)]
pub struct TurnActivity {
    pub id: TurnId,
    pub status: TurnStatus,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryTurn {
    #[serde(flatten)]
    pub activity: TurnActivity,
    pub items: Vec<Value>,
    pub started_at: Option<i64>,
    pub completed_at: Option<i64>,
    pub error: Option<Value>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ChatScope {
    connection: ConnectionIdentity,
    thread: ThreadId,
}

#[derive(Debug)]
pub struct ChatRead<T> {
    scope: ChatScope,
    data: T,
}

impl<T> ChatRead<T> {
    pub fn for_selection(
        &self,
        connection: &ConnectionIdentity,
        thread: &ThreadId,
    ) -> Result<&T, BrowseError> {
        if &self.scope.connection != connection || &self.scope.thread != thread {
            return Err(BrowseError::StaleChatRead);
        }
        if let Some(checkout) = &connection.workspace.checkout {
            checkout.revalidate()?;
        }
        Ok(&self.data)
    }
}

#[derive(Debug)]
pub struct TurnCursor {
    scope: ChatScope,
    view: TurnView,
    token: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TurnView {
    Status,
    History,
}

impl TurnView {
    fn request_options(self) -> (&'static str, u32) {
        match self {
            Self::Status => ("notLoaded", 100),
            Self::History => ("full", 20),
        }
    }
}

impl CodexBrowser {
    pub async fn thread_summary(
        &self,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<ChatRead<ChatSummary>, BrowseError> {
        #[derive(Deserialize)]
        struct Response {
            thread: ChatSummary,
        }

        let checkout = self.checkout()?;
        checkout.revalidate()?;
        let response: Response = self
            .read(
                "thread/read",
                json!({"threadId": thread.0, "includeTurns": false}),
                timeout,
            )
            .await?;
        if &response.thread.thread.id != thread {
            return Err(BrowseError::WrongThread);
        }
        checkout.validate_reported(&response.thread.thread.cwd)?;
        Ok(ChatRead {
            scope: ChatScope {
                connection: self.client.identity().clone(),
                thread: thread.clone(),
            },
            data: response.thread,
        })
    }

    pub async fn turn_statuses(
        &self,
        chat: &ChatRead<ChatSummary>,
        cursor: Option<&TurnCursor>,
        timeout: Duration,
    ) -> Result<ChatRead<Page<TurnActivity, TurnCursor>>, BrowseError> {
        self.turn_page(chat, cursor, TurnView::Status, timeout)
            .await
    }

    pub async fn history(
        &self,
        chat: &ChatRead<ChatSummary>,
        cursor: Option<&TurnCursor>,
        timeout: Duration,
    ) -> Result<ChatRead<Page<HistoryTurn, TurnCursor>>, BrowseError> {
        self.turn_page(chat, cursor, TurnView::History, timeout)
            .await
    }

    async fn turn_page<T: DeserializeOwned>(
        &self,
        chat: &ChatRead<ChatSummary>,
        cursor: Option<&TurnCursor>,
        view: TurnView,
        timeout: Duration,
    ) -> Result<ChatRead<Page<T, TurnCursor>>, BrowseError> {
        let scope = &chat.scope;
        if &scope.connection != self.client.identity() {
            return Err(BrowseError::StaleChatRead);
        }
        let checkout = self.checkout()?;
        let cwd = &chat.data.thread.cwd;
        checkout.validate_reported(cwd)?;
        let token = match cursor {
            Some(cursor) if &cursor.scope == scope && cursor.view == view => Some(&cursor.token),
            Some(_) => return Err(BrowseError::CursorScope),
            None => None,
        };
        let (items_view, limit) = view.request_options();
        let response: WirePage<T> = self
            .read(
                "thread/turns/list",
                json!({
                    "threadId": scope.thread.0,
                    "itemsView": items_view,
                    "sortDirection": "desc",
                    "cursor": token,
                    "limit": limit,
                }),
                timeout,
            )
            .await?;
        checkout.validate_reported(cwd)?;
        Ok(ChatRead {
            scope: scope.clone(),
            data: response.map_cursor(|token| TurnCursor {
                scope: scope.clone(),
                view,
                token,
            }),
        })
    }
}
