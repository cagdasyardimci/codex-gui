use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::{TranscriptAttachment, subscription::HistoryInsertion};

mod commands;
mod residency;
pub use commands::{CommandUpdate, TranscriptCommand};
use residency::{ResidentTurns, RowCost};

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
    #[serde(default)]
    pub attachments: Vec<TranscriptAttachment>,
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
            attachments: Vec::new(),
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
    #[serde(skip)]
    #[ts(skip)]
    residency: ResidentTurns,
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

    pub(super) fn insert(&mut self, position: usize, added: Self) -> Vec<TranscriptItem> {
        let incoming: Vec<_> = added
            .items
            .into_iter()
            .filter(|item| !self.positions.contains_key(&item.item_id))
            .collect();
        if incoming.is_empty() {
            return incoming;
        }
        self.items
            .splice(position..position, incoming.iter().cloned());
        self.reindex();
        incoming
    }

    pub(super) fn merge(&mut self, added: Self, order: &[String]) -> Vec<HistoryInsertion> {
        let rank: HashMap<_, _> = order
            .iter()
            .enumerate()
            .map(|(index, turn)| (turn.as_str(), index))
            .collect();
        let rank_of = |row: &TranscriptItem| {
            rank.get(row.turn_id.as_str())
                .copied()
                .unwrap_or(usize::MAX)
        };
        let mut incoming: Vec<_> = added
            .items
            .into_iter()
            .filter(|item| !self.positions.contains_key(&item.item_id))
            .collect();
        if incoming.is_empty() {
            return Vec::new();
        }
        incoming.sort_by_key(&rank_of);
        let mut insertions: Vec<HistoryInsertion> = Vec::new();
        let mut retained = std::mem::take(&mut self.items).into_iter().peekable();
        for row in incoming {
            while retained
                .peek()
                .is_some_and(|current| rank_of(current) <= rank_of(&row))
            {
                self.items.push(retained.next().expect("peeked row"));
            }
            let position = self.items.len() as u32;
            if let Some(last) = insertions
                .last_mut()
                .filter(|last| last.position + last.rows.len() as u32 == position)
            {
                last.rows.push(row.clone());
            } else {
                insertions.push(HistoryInsertion {
                    position,
                    rows: vec![row.clone()],
                });
            }
            self.items.push(row);
        }
        self.items.extend(retained);
        self.reindex();
        insertions
    }

    fn reindex(&mut self) {
        self.positions.clear();
        self.commands.clear();
        for (row, item) in self.items.iter().enumerate() {
            self.positions.insert(item.item_id.clone(), row);
            for (index, command) in item.commands.iter().enumerate() {
                self.commands.insert(command.id.clone(), (row, index));
            }
        }
        self.residency.recompute(&self.items);
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
                        let cost = RowCost::from(item);
                        self.residency.replace(cost);
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
                self.residency.replace(RowCost::from(item));
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
        self.residency.replace(RowCost::from(&item));
        self.items.push(item);
        index
    }

    pub(super) fn set_viewport(&mut self, anchor: Option<String>, protected: Vec<String>) {
        self.residency.set_viewport(anchor, protected);
    }

    pub(super) fn protect_landing(&mut self, turn: String) {
        self.residency.protect_landing(turn);
    }

    pub(super) fn trim(&mut self) -> Vec<String> {
        let evicted = self.residency.evictions(&self.items);
        if evicted.is_empty() {
            return evicted;
        }
        let excluded: std::collections::HashSet<_> = evicted.iter().collect();
        self.items.retain(|row| !excluded.contains(&row.turn_id));
        self.reindex();
        evicted
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
