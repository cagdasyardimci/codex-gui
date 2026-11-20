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
    append_turn_with_speech(view, checkout, turn, active, false);
}

pub(super) fn append_turn_with_speech(
    view: &mut TranscriptView,
    checkout: &CheckoutIdentity,
    turn: &HistoryTurn,
    active: &mut Vec<String>,
    canonical: bool,
) {
    append_turn_items(
        view,
        checkout,
        &turn.activity,
        &turn.items,
        active,
        canonical,
    );
}

pub(super) fn append_turn_items(
    view: &mut TranscriptView,
    checkout: &CheckoutIdentity,
    activity: &TurnActivity,
    items: &[Value],
    active: &mut Vec<String>,
    canonical: bool,
) {
    let completed = activity.status != TurnStatus::InProgress;
    let id = &activity.id.0;
    let voice_turn = items.iter().any(|value| legacy_record(value).is_some());
    for value in items {
        if let Some(speech) = legacy_record(value) {
            if !canonical {
                let source = value["id"].as_str().unwrap_or_default();
                for (index, (role, text)) in speech.into_iter().enumerate() {
                    let mut item = TranscriptItem::message(
                        format!("speech/legacy/{id}/{source}/{index}"),
                        id.clone(),
                        text,
                        true,
                        role,
                    );
                    item.spoken = true;
                    view.push_message(item);
                }
            }
        } else if let Some(command) = command_item(id, value) {
            view.apply_command(command);
        } else if let Some(mut item) = message_item(checkout, id, value, completed)
            && (!voice_turn || item.show_voice_response())
        {
            if !item.completed && item.role == TranscriptRole::Assistant {
                active.push(item.item_id.clone());
            }
            view.push_message(item);
        }
    }
}

fn legacy_record(value: &Value) -> Option<Vec<(TranscriptRole, String)>> {
    if value["type"] != "userMessage" {
        return None;
    }
    let input = value["content"].as_array()?;
    let [part] = input.as_slice() else {
        return None;
    };
    if part["type"] != "text" {
        return None;
    }
    let body = part["text"]
        .as_str()?
        .strip_prefix("<realtime_delegation>\n")?
        .strip_suffix("\n</realtime_delegation>")?;
    let body = body
        .strip_prefix("  <source>transcript_tail_flush</source>\n")
        .unwrap_or(body);
    let (_, tail) = body.strip_prefix("  <input>")?.split_once("</input>")?;
    if tail.is_empty() {
        return Some(Vec::new());
    }
    let transcript = tail
        .strip_prefix("\n  <transcript_delta>")?
        .strip_suffix("</transcript_delta>")?;
    let mut turns: Vec<(TranscriptRole, String)> = Vec::new();
    for line in transcript.split('\n') {
        if let Some(text) = line.strip_prefix("user: ") {
            turns.push((TranscriptRole::User, text.into()));
        } else if let Some(text) = line.strip_prefix("assistant: ") {
            turns.push((TranscriptRole::Assistant, text.into()));
        } else if let Some((_, text)) = turns.last_mut() {
            text.push('\n');
            text.push_str(line);
        }
    }
    for (_, text) in &mut turns {
        *text = text
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
            .trim()
            .into();
    }
    turns.retain(|(_, text)| !text.is_empty());
    Some(turns)
}

pub(super) fn message_item(
    checkout: &CheckoutIdentity,
    turn: &str,
    value: &Value,
    completed: bool,
) -> Option<TranscriptItem> {
    if legacy_record(value).is_some() {
        return None;
    }
    let id = value["id"].as_str()?;
    let kind = value["type"].as_str()?;
    let role = match kind {
        "agentMessage" | "exitedReviewMode" => TranscriptRole::Assistant,
        "userMessage" => TranscriptRole::User,
        _ => return None,
    };
    let text = match role {
        TranscriptRole::Assistant => value[if kind == "exitedReviewMode" {
            "review"
        } else {
            "text"
        }]
        .as_str()?
        .to_owned(),
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
        if role == TranscriptRole::User {
            item.attachments = crate::transcript_ipc::local_attachments(checkout, value);
            item.editable_prompt = super::prompt_revision::is_editable_prompt(value);
        } else {
            item.local_images = local_images(checkout, &item.text, value);
        }
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
