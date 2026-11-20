use std::collections::{HashMap, HashSet};

use super::TranscriptItem;

const MAX_RESIDENT_TURNS: usize = 75;
const MAX_RESIDENT_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Debug, Default, PartialEq)]
pub(super) struct ResidentTurns {
    bytes: usize,
    turns: HashMap<String, usize>,
    rows: HashMap<String, RowCost>,
    protected: HashSet<String>,
    anchor: Option<String>,
    landing: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct RowCost {
    id: String,
    turn: String,
    bytes: usize,
}

impl RowCost {
    pub(super) fn from(row: &TranscriptItem) -> Self {
        let utf8 = row.local_images.iter().map(String::len).sum::<usize>();
        let attachments = row
            .attachments
            .iter()
            .map(|image| image.label.len() + image.relative_path.len() + 16)
            .sum::<usize>();
        let commands = row
            .commands
            .iter()
            .map(|command| {
                64 + command.id.len()
                    + command.command.len()
                    + command.output.as_ref().map_or(0, String::len)
            })
            .sum::<usize>();
        Self {
            id: row.item_id.clone(),
            turn: row.turn_id.clone(),
            bytes: 128
                + row.item_id.len()
                + row.turn_id.len()
                + row.text.len()
                + utf8
                + commands
                + attachments,
        }
    }
}

impl ResidentTurns {
    pub(super) fn replace(&mut self, cost: RowCost) {
        self.bytes += cost.bytes;
        *self.turns.entry(cost.turn.clone()).or_default() += cost.bytes;
        if let Some(prior) = self.rows.insert(cost.id.clone(), cost) {
            self.bytes -= prior.bytes;
            if let Some(bytes) = self.turns.get_mut(&prior.turn) {
                *bytes -= prior.bytes;
                if *bytes == 0 {
                    self.turns.remove(&prior.turn);
                }
            }
        }
    }

    pub(super) fn recompute(&mut self, rows: &[TranscriptItem]) {
        self.bytes = 0;
        self.turns.clear();
        self.rows.clear();
        for row in rows {
            self.replace(RowCost::from(row));
        }
    }

    pub(super) fn set_viewport(&mut self, anchor: Option<String>, protected: Vec<String>) {
        self.anchor = anchor;
        self.protected = protected.into_iter().collect();
        self.landing = None;
    }

    pub(super) fn protect_landing(&mut self, turn: String) {
        self.landing = Some(turn);
    }

    pub(super) fn evictions(&self, rows: &[TranscriptItem]) -> Vec<String> {
        self.plan(rows, MAX_RESIDENT_TURNS, MAX_RESIDENT_BYTES)
    }

    fn plan(
        &self,
        rows: &[TranscriptItem],
        maximum_turns: usize,
        maximum_bytes: usize,
    ) -> Vec<String> {
        if self.turns.len() <= maximum_turns && self.bytes <= maximum_bytes {
            return Vec::new();
        }
        let mut seen = HashSet::new();
        let ordered: Vec<_> = rows
            .iter()
            .filter_map(|row| {
                seen.insert(row.turn_id.as_str())
                    .then_some(row.turn_id.as_str())
            })
            .collect();
        let anchor = self
            .anchor
            .as_deref()
            .and_then(|turn| ordered.iter().position(|current| *current == turn))
            .unwrap_or(0);
        let newest = ordered.last().copied();
        let mut candidates: Vec<_> = ordered
            .iter()
            .enumerate()
            .filter(|(index, turn)| {
                *index != anchor
                    && Some(**turn) != newest
                    && self.landing.as_deref() != Some(**turn)
                    && !self.protected.contains(**turn)
            })
            .collect();
        candidates
            .sort_unstable_by_key(|(index, _)| (std::cmp::Reverse(index.abs_diff(anchor)), *index));
        let mut bytes = self.bytes;
        let mut turns = self.turns.len();
        let mut evicted = Vec::new();
        for (_, turn) in candidates {
            if turns <= maximum_turns && bytes <= maximum_bytes {
                break;
            }
            bytes -= self.turns[*turn];
            turns -= 1;
            evicted.push((*turn).to_owned());
        }
        evicted
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ipc::TranscriptRole;

    #[test]
    fn retains_viewport_selection_and_landing_while_evicting_far_history() {
        let rows: Vec<_> = (0..8)
            .map(|id| {
                TranscriptItem::message(
                    format!("row-{id}"),
                    format!("turn-{id}"),
                    "example".into(),
                    true,
                    TranscriptRole::Assistant,
                )
            })
            .collect();
        let mut residency = ResidentTurns::default();
        residency.recompute(&rows);
        residency.set_viewport(Some("turn-2".into()), vec!["turn-3".into()]);
        residency.protect_landing("turn-1".into());
        assert_eq!(
            residency.plan(&rows, 4, usize::MAX),
            ["turn-6", "turn-5", "turn-0", "turn-4"]
        );
        assert_eq!(
            residency.plan(&rows, 1, 1),
            ["turn-6", "turn-5", "turn-0", "turn-4"]
        );
    }
}
