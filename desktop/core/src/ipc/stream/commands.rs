use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::{RowCost, TranscriptItem, TranscriptRole, TranscriptView};

const MAX_GROUPED_COMMANDS: usize = 64;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptCommand {
    pub id: String,
    pub command: String,
    pub output: Option<String>,
    pub completed: bool,
    pub exit_code: Option<i32>,
}

pub enum CommandUpdate {
    Item {
        turn_id: String,
        command: TranscriptCommand,
    },
    Output {
        item_id: String,
        delta: String,
    },
}

impl TranscriptView {
    pub fn apply_command(&mut self, change: CommandUpdate) -> Option<&TranscriptItem> {
        if self.completed {
            return None;
        }
        let row = match change {
            CommandUpdate::Item { turn_id, command } => self.update_command(turn_id, command)?,
            CommandUpdate::Output { item_id, delta } => {
                let &(row, index) = self.commands.get(&item_id)?;
                let command = self.items.get_mut(row)?.commands.get_mut(index)?;
                if delta.is_empty() || command.completed {
                    return None;
                }
                command
                    .output
                    .get_or_insert_with(String::new)
                    .push_str(&delta);
                row
            }
        };
        let item = &mut self.items[row];
        item.revision += 1;
        item.completed = item.commands.iter().all(|command| command.completed);
        self.residency.replace(RowCost::from(item));
        Some(item)
    }

    fn update_command(&mut self, turn_id: String, mut command: TranscriptCommand) -> Option<usize> {
        if let Some(&(row, index)) = self.commands.get(&command.id) {
            let current = self.items.get_mut(row)?.commands.get_mut(index)?;
            if current.completed && !command.completed {
                return None;
            }
            if command.output.is_none() {
                command.output.clone_from(&current.output);
            }
            if current == &command {
                return None;
            }
            *current = command;
            return Some(row);
        }
        let continuing = self.items.last().is_some_and(|row| {
            row.role == TranscriptRole::Commands
                && row.turn_id == turn_id
                && row.commands.len() < MAX_GROUPED_COMMANDS
        });
        let row = if continuing {
            self.items.len() - 1
        } else {
            self.push(TranscriptItem::message(
                format!("{}/commands", command.id),
                turn_id,
                String::new(),
                false,
                TranscriptRole::Commands,
            ))
        };
        let commands = &mut self.items[row].commands;
        self.commands
            .insert(command.id.clone(), (row, commands.len()));
        commands.push(command);
        Some(row)
    }
}
