use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use ts_rs::TS;

mod commands;
pub use commands::{CommandUpdate, TranscriptCommand};

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
    Commands,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TranscriptItem {
    pub item_id: String,
    pub text: String,
    pub completed: bool,
    pub role: TranscriptRole,
    pub turn_id: String,
    pub revision: u32,
    pub commands: Vec<TranscriptCommand>,
    pub local_images: Vec<String>,
}

impl TranscriptItem {
    pub fn message(
        item_id: String,
        turn_id: String,
        text: String,
        completed: bool,
        role: TranscriptRole,
    ) -> Self {
        Self {
            item_id,
            text,
            completed,
            role,
            turn_id,
            revision: 0,
            commands: Vec::new(),
            local_images: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptView {
    pub items: Vec<TranscriptItem>,
    pub completed: bool,
    pub generation: u32,
    #[serde(skip)]
    #[ts(skip)]
    positions: HashMap<String, usize>,
    #[serde(skip)]
    #[ts(skip)]
    commands: HashMap<String, (usize, usize)>,
}

impl TranscriptView {
    pub fn push_message(&mut self, mut item: TranscriptItem) {
        if self.positions.contains_key(&item.item_id) {
            self.apply(&mut StreamChange::FinalItem(item));
            return;
        }
        item.revision = 1;
        self.push(item);
    }

    pub(super) fn matching_row(&self, item_id: &str, revision: u32) -> Option<&TranscriptItem> {
        let item = self.items.get(*self.positions.get(item_id)?)?;
        (item.revision == revision).then_some(item)
    }

    pub(super) fn prepend(&mut self, earlier: Self) -> Vec<TranscriptItem> {
        let mut prefix: Vec<_> = earlier
            .items
            .into_iter()
            .filter(|item| !self.positions.contains_key(&item.item_id))
            .collect();
        if prefix.is_empty() {
            return prefix;
        }
        let inserted = prefix.clone();
        prefix.append(&mut self.items);
        self.items = prefix;
        self.positions.clear();
        self.commands.clear();
        for (row, item) in self.items.iter().enumerate() {
            self.positions.insert(item.item_id.clone(), row);
            for (index, command) in item.commands.iter().enumerate() {
                self.commands.insert(command.id.clone(), (row, index));
            }
        }
        inserted
    }

    pub(super) fn apply(&mut self, change: &mut StreamChange) -> bool {
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
                        item.revision += 1;
                        changed = true;
                    }
                }
                changed
            }
            StreamChange::ItemCompleted(id) => {
                let item = self.item(id);
                if item.completed {
                    return false;
                }
                item.completed = true;
                item.revision += 1;
                true
            }
            StreamChange::FinalItem(final_item) => {
                let Some(&index) = self.positions.get(&final_item.item_id) else {
                    final_item.revision = 1;
                    self.push(final_item.clone());
                    return true;
                };
                let item = &mut self.items[index];
                if item.completed && !final_item.completed {
                    return false;
                }
                if !final_item.completed && final_item.text.is_empty() && !item.text.is_empty() {
                    final_item.text.clone_from(&item.text);
                }
                final_item.revision = item.revision;
                if item == final_item {
                    return false;
                }
                final_item.revision += 1;
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
        if let Some(&index) = self.positions.get(id) {
            return &mut self.items[index];
        }
        let turn = id.split_once('/').map_or("", |(turn, _)| turn);
        self.push(TranscriptItem::message(
            id.to_owned(),
            turn.to_owned(),
            String::new(),
            false,
            TranscriptRole::Assistant,
        ));
        self.items.last_mut().expect("inserted transcript item")
    }

    fn push(&mut self, item: TranscriptItem) -> usize {
        let index = self.items.len();
        self.positions.insert(item.item_id.clone(), index);
        self.items.push(item);
        index
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
