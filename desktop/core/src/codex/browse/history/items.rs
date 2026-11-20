use std::collections::HashSet;

use super::*;

const MAX_ITEM_PAGES: usize = 32;
const MAX_ITEM_PAGE: usize = 100;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TurnItemRead {
    Preview,
    Complete,
}

#[derive(Debug)]
pub struct TurnItems {
    pub id: TurnId,
    pub items: Vec<Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireTurnItem {
    turn_id: TurnId,
    item: Value,
}

impl CodexBrowser {
    pub async fn turn_items(
        &self,
        chat: &ChatRead<ChatSummary>,
        turn: &TurnId,
        read: TurnItemRead,
        timeout: Duration,
    ) -> Result<ChatRead<TurnItems>, BrowseError> {
        self.validate_chat(chat)?;
        let scope = &chat.scope;
        let mut page = self
            .turn_item_page(scope, turn, None, "asc", timeout)
            .await?;
        let mut items = Vec::new();
        let mut ids = HashSet::new();
        keep_items(&mut items, &mut ids, page.data.drain(..))?;
        if read == TurnItemRead::Preview {
            if page.next_cursor.is_some() {
                let last = self
                    .turn_item_page(scope, turn, None, "desc", timeout)
                    .await?;
                keep_items(&mut items, &mut ids, last.data.into_iter().rev())?;
            }
            items.retain(|item| {
                matches!(item["type"].as_str(), Some("userMessage" | "agentMessage"))
            });
        } else {
            let mut cursors = HashSet::new();
            while let Some(cursor) = page.next_cursor {
                if cursors.len() + 1 >= MAX_ITEM_PAGES || !cursors.insert(cursor.clone()) {
                    return Err(BrowseError::TurnItemsPagination);
                }
                page = self
                    .turn_item_page(scope, turn, Some(&cursor), "asc", timeout)
                    .await?;
                keep_items(&mut items, &mut ids, page.data.drain(..))?;
            }
        }
        self.validate_chat(chat)?;
        Ok(ChatRead {
            scope: scope.clone(),
            data: TurnItems {
                id: turn.clone(),
                items,
            },
        })
    }

    async fn turn_item_page(
        &self,
        scope: &ChatScope,
        turn: &TurnId,
        cursor: Option<&str>,
        direction: &str,
        timeout: Duration,
    ) -> Result<WirePage<WireTurnItem>, BrowseError> {
        let page: WirePage<WireTurnItem> = self
            .read(
                "thread/items/list",
                json!({
                    "threadId": scope.thread.0, "turnId": turn.0, "cursor": cursor,
                    "sortDirection": direction, "limit": MAX_ITEM_PAGE,
                }),
                timeout,
            )
            .await?;
        if page.data.len() > MAX_ITEM_PAGE || page.data.iter().any(|row| &row.turn_id != turn) {
            return Err(BrowseError::TurnItemsPagination);
        }
        Ok(page)
    }
}

fn keep_items(
    items: &mut Vec<Value>,
    ids: &mut HashSet<String>,
    entries: impl Iterator<Item = WireTurnItem>,
) -> Result<(), BrowseError> {
    for entry in entries {
        let Some(id) = entry.item["id"].as_str().filter(|id| !id.is_empty()) else {
            return Err(BrowseError::TurnItemsPagination);
        };
        if ids.insert(id.to_owned()) {
            items.push(entry.item);
        }
    }
    Ok(())
}
