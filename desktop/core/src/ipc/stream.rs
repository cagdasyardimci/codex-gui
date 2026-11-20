use serde::{Deserialize, Serialize};
use ts_rs::TS;

const MAX_PENDING_BYTES: usize = 16 * 1024;
const MAX_PENDING_ITEMS: usize = 64;

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TextBatch {
    pub item_id: String,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum StreamChange {
    Text(Vec<TextBatch>),
    ItemCompleted(String),
    FinalItem(TranscriptItem),
    Completed,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum TranscriptRole {
    User,
    Assistant,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptItem {
    pub item_id: String,
    pub text: String,
    pub completed: bool,
    pub role: TranscriptRole,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptView {
    pub items: Vec<TranscriptItem>,
    pub completed: bool,
}

impl TranscriptView {
    pub(super) fn apply(&mut self, change: &StreamChange) -> bool {
        if self.completed {
            return false;
        }
        match change {
            StreamChange::Text(batches) => {
                let mut changed = false;
                for batch in batches {
                    if batch.text.is_empty() {
                        continue;
                    }
                    let item = self.item(&batch.item_id);
                    if !item.completed {
                        item.text.push_str(&batch.text);
                        changed = true;
                    }
                }
                changed
            }
            StreamChange::ItemCompleted(id) => {
                let item = self.item(id);
                !std::mem::replace(&mut item.completed, true)
            }
            StreamChange::FinalItem(final_item) => {
                let item = self.item(&final_item.item_id);
                if item == final_item {
                    return false;
                }
                *item = final_item.clone();
                true
            }
            StreamChange::Completed => {
                self.completed = true;
                true
            }
        }
    }

    fn item(&mut self, id: &str) -> &mut TranscriptItem {
        if let Some(index) = self.items.iter().position(|item| item.item_id == id) {
            return &mut self.items[index];
        }
        self.items.push(TranscriptItem {
            item_id: id.to_owned(),
            text: String::new(),
            completed: false,
            role: TranscriptRole::Assistant,
        });
        self.items.last_mut().expect("inserted transcript item")
    }
}

#[derive(Default)]
pub struct TextBatcher {
    pending: Vec<TextBatch>,
    bytes: usize,
}

impl TextBatcher {
    pub fn append(&mut self, item_id: String, text: String) -> Option<StreamChange> {
        if text.is_empty() {
            return None;
        }
        self.bytes += text.len();
        if let Some(batch) = self
            .pending
            .iter_mut()
            .find(|batch| batch.item_id == item_id)
        {
            batch.text.push_str(&text);
        } else {
            self.pending.push(TextBatch { item_id, text });
        }
        if self.bytes >= MAX_PENDING_BYTES || self.pending.len() >= MAX_PENDING_ITEMS {
            return self.flush();
        }
        None
    }

    pub fn flush(&mut self) -> Option<StreamChange> {
        if self.pending.is_empty() {
            return None;
        }
        self.bytes = 0;
        Some(StreamChange::Text(std::mem::take(&mut self.pending)))
    }

    pub fn finish(&mut self, terminal: StreamChange) -> impl Iterator<Item = StreamChange> + use<> {
        self.flush().into_iter().chain(std::iter::once(terminal))
    }
}
