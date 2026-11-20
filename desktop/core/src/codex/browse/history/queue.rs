use std::{collections::HashSet, time::Duration};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::time::Instant;

use super::{super::PAGE_LIMIT, BrowseError, ChatRead, ChatSummary, CodexBrowser, WirePage};
use crate::codex::{Delivery, RequestError};

const METHOD: &str = "thread/queue/list";

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueuedSubmission {
    pub id: String,
    pub client_user_message_id: String,
    pub input: Vec<Value>,
}

#[derive(Debug)]
pub enum QueueSnapshot {
    Available(Vec<QueuedSubmission>),
    Unsupported,
}

impl CodexBrowser {
    pub async fn queue_snapshot(
        &self,
        chat: &ChatRead<ChatSummary>,
        timeout: Duration,
    ) -> Result<ChatRead<QueueSnapshot>, BrowseError> {
        let deadline = Instant::now() + timeout;
        self.validate_chat(chat)?;
        let mut entries = Vec::new();
        let mut seen = HashSet::new();
        let mut cursors = HashSet::new();
        let mut cursor = None;
        let data =
            loop {
                let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                    return Err(RequestError::Timeout(Delivery::Unsent).into());
                };
                let page = self.read::<WirePage<QueuedSubmission>>(
                METHOD,
                json!({"threadId": chat.scope.thread.0, "cursor": cursor, "limit": PAGE_LIMIT}),
                remaining,
            ).await;
                self.validate_chat(chat)?;
                let page = match page {
                    Ok(page) => page,
                    Err(error) if cursor.is_none() && explicitly_unsupported(&error) => {
                        break QueueSnapshot::Unsupported;
                    }
                    Err(error) => return Err(error),
                };
                for item in page.data {
                    if item.id.is_empty()
                        || item.client_user_message_id.is_empty()
                        || !seen.insert(item.id.clone())
                    {
                        return Err(BrowseError::QueuePagination);
                    }
                    entries.push(item);
                }
                let Some(next) = page.next_cursor else {
                    break QueueSnapshot::Available(entries);
                };
                if !cursors.insert(next.clone()) {
                    return Err(BrowseError::QueuePagination);
                }
                cursor = Some(next);
            };
        Ok(ChatRead {
            scope: chat.scope.clone(),
            data,
        })
    }
}

fn explicitly_unsupported(error: &BrowseError) -> bool {
    let BrowseError::Request(RequestError::Remote(error)) = error else {
        return false;
    };
    error.code == -32601
        || (error.code == -32600
            && error
                .message
                .contains("unknown variant `thread/queue/list`"))
}
