use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{HistoryTurn, TurnActivity, TurnStatus},
    ipc::{
        CommandUpdate, TranscriptCommand, TranscriptItem, TranscriptRole, TranscriptView,
        present_question_reply,
    },
};
use serde_json::Value;

use crate::transcript_ipc::local_images;

pub(super) fn transcript_id(turn: &str, item: &str) -> String {
    format!("{turn}/{item}")
}

pub(super) fn append_turn(
    view: &mut TranscriptView,
    checkout: &CheckoutIdentity,
    turn: &HistoryTurn,
    active: &mut Vec<String>,
) {
    append_turn_items(view, checkout, &turn.activity, &turn.items, active);
}

pub(super) fn append_turn_items(
    view: &mut TranscriptView,
    checkout: &CheckoutIdentity,
    activity: &TurnActivity,
    items: &[Value],
    active: &mut Vec<String>,
) {
    let completed = activity.status != TurnStatus::InProgress;
    let id = &activity.id.0;
    for value in items {
        if let Some(command) = command_item(id, value) {
            view.apply_command(command);
        } else if let Some(item) = message_item(checkout, id, value, completed) {
            if !item.completed && item.role == TranscriptRole::Assistant {
                active.push(item.item_id.clone());
            }
            view.push_message(item);
        }
    }
}

pub(super) fn message_item(
    checkout: &CheckoutIdentity,
    turn: &str,
    value: &Value,
    completed: bool,
) -> Option<TranscriptItem> {
    let id = value["id"].as_str()?;
    let role = match value["type"].as_str()? {
        "agentMessage" => TranscriptRole::Assistant,
        "userMessage" => TranscriptRole::User,
        _ => return None,
    };
    let text = match role {
        TranscriptRole::Assistant => value["text"].as_str()?.to_owned(),
        TranscriptRole::User => {
            let source = value["content"]
                .as_array()?
                .iter()
                .filter(|entry| entry["type"] == "text")
                .filter_map(|entry| entry["text"].as_str())
                .collect::<Vec<_>>()
                .join("\n");
            present_question_reply(&source).into_owned()
        }
        TranscriptRole::Commands => unreachable!(),
    };
    let mut item = TranscriptItem::message(
        transcript_id(turn, id),
        turn.to_owned(),
        text,
        completed || role == TranscriptRole::User,
        role,
    );
    if item.completed {
        item.local_images = local_images(checkout, &item.text, value);
    }
    Some(item)
}

pub(super) fn command_item(turn: &str, value: &Value) -> Option<CommandUpdate> {
    if value["type"] != "commandExecution" {
        return None;
    }
    let id = transcript_id(turn, value["id"].as_str()?);
    Some(CommandUpdate::Item {
        turn_id: turn.to_owned(),
        command: TranscriptCommand {
            id,
            command: value["command"].as_str()?.to_owned(),
            output: value["aggregatedOutput"].as_str().map(str::to_owned),
            completed: matches!(
                value["status"].as_str(),
                Some("completed" | "failed" | "declined")
            ),
            exit_code: value["exitCode"]
                .as_i64()
                .and_then(|number| i32::try_from(number).ok()),
        },
    })
}
