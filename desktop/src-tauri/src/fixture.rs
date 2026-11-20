use std::{
    env,
    io::{self, Write},
    process::Stdio,
    time::Duration,
};

use codex_gui_core::codex::{JsonlReader, ServerEvent, ServerMessage, read_message};
use codex_gui_core::ipc::{StreamChange, TextBatcher, TranscriptItem, WorkspaceId};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tauri::{AppHandle, Manager, State, WebviewWindow};
use tokio::{process::Command, time::MissedTickBehavior};

use crate::project_ipc::ProjectIpc;

pub const CHILD_ARGUMENT: &str = "--diagnostic-fixture-stdio";
const STREAMING_SCENARIO: &str =
    include_str!("../../../Tests/E2E/MockBackend/mock_backend/scenarios/streaming.json");
const PRIMARY_ITEM: &str = "fixture-main-item";
const SECONDARY_ITEM: &str = "fixture-secondary-item";
const SECONDARY_TEXT: [&str; 2] = ["cafe\u{301} ", "漢字 👩🏽‍💻"];

#[derive(Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Verification {
    None,
    Streaming,
    Media,
}

#[derive(Deserialize)]
struct Scenario {
    chunks: Vec<String>,
}

fn scenario() -> serde_json::Result<Scenario> {
    serde_json::from_str(STREAMING_SCENARIO)
}

pub fn write_fixture() -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    for (group, chunks) in scenario()?.chunks.chunks(4).enumerate() {
        let mut burst = Vec::new();
        for (index, text) in chunks.iter().enumerate() {
            write_notification(
                &mut burst,
                "item/agentMessage/delta",
                json!({"itemId": PRIMARY_ITEM, "delta": text}),
            )?;
            if group == 0
                && let Some(text) = SECONDARY_TEXT.get(index)
            {
                write_notification(
                    &mut burst,
                    "item/agentMessage/delta",
                    json!({"itemId": SECONDARY_ITEM, "delta": text}),
                )?;
            }
        }
        if group == 0 {
            write_notification(
                &mut burst,
                "item/completed",
                json!({"item": {"id": SECONDARY_ITEM}}),
            )?;
        }
        stdout.write_all(&burst)?;
        stdout.flush()?;
        std::thread::sleep(Duration::from_millis(75));
    }
    write_notification(
        &mut stdout,
        "item/completed",
        json!({"item": {"id": PRIMARY_ITEM}}),
    )?;
    write_notification(&mut stdout, "turn/completed", json!({}))?;
    stdout.flush()?;
    Ok(())
}

fn write_notification(mut output: impl Write, method: &str, params: Value) -> io::Result<()> {
    serde_json::to_writer(&mut output, &json!({"method": method, "params": params}))?;
    output.write_all(b"\n")
}

#[tauri::command]
pub async fn stream_fixture(
    app: AppHandle,
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
) -> Result<bool, String> {
    if *verification != Verification::Streaming {
        return Err("fixture verification was not requested at launch".into());
    }
    let Some(workspace) = state
        .start_fixture(&window)
        .map_err(|error| format!("{error:?}"))?
    else {
        return Ok(false);
    };
    tauri::async_runtime::spawn(async move {
        match tokio::time::timeout(
            Duration::from_secs(15),
            send_fixture(&app.state::<ProjectIpc>(), workspace),
        )
        .await
        {
            Ok(Ok(())) => return,
            Ok(Err(error)) => eprintln!("{error}"),
            Err(_) => eprintln!("stream fixture timed out"),
        }
        app.exit(1);
    });
    Ok(true)
}

async fn send_fixture(
    state: &ProjectIpc,
    workspace: WorkspaceId,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut command = Command::new(env::current_exe()?);
    command
        .arg(CHILD_ARGUMENT)
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stdout(Stdio::piped());
    #[cfg(windows)]
    {
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command.spawn()?;
    let stdout = child.stdout.take().expect("fixture stdout is piped");
    let mut reader = JsonlReader::new(stdout, 64 * 1024);
    let mut timer = tokio::time::interval(Duration::from_millis(20));
    timer.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut batcher = TextBatcher::default();
    let mut input_deltas = 0;
    let mut published_batches = 0;
    let mut turn_finished = false;
    let mut publish = |change: StreamChange| {
        if matches!(&change, StreamChange::Text(_)) {
            published_batches += 1;
        }
        state
            .publish_stream(workspace, change)
            .then_some(())
            .ok_or("fixture stream lost its workspace")
    };
    loop {
        let message = tokio::select! {
            biased;
            _ = timer.tick() => {
                if let Some(batch) = batcher.flush() {
                    publish(batch)?;
                }
                continue;
            }
            message = read_message(&mut reader) => message?,
        };
        let Some(message) = message else { break };
        if turn_finished {
            return Err("fixture sent a notification after turn completion".into());
        }
        let ServerMessage::Event(ServerEvent::Notification { method, params }) = message else {
            return Err("fixture sent an unexpected envelope".into());
        };
        match method.as_str() {
            "item/agentMessage/delta" => {
                let id = params["itemId"]
                    .as_str()
                    .ok_or("invalid fixture item identity")?;
                let text = params["delta"].as_str().ok_or("invalid fixture delta")?;
                input_deltas += 1;
                if let Some(batch) = batcher.append(id.to_owned(), text.to_owned()) {
                    publish(batch)?;
                }
            }
            "item/completed" => {
                let id = params["item"]["id"]
                    .as_str()
                    .ok_or("invalid fixture item identity")?;
                for change in batcher.finish(StreamChange::ItemCompleted(id.to_owned())) {
                    publish(change)?;
                }
            }
            "turn/completed" => turn_finished = true,
            _ => return Err("fixture sent an unexpected notification".into()),
        }
    }
    if !turn_finished || !child.wait().await?.success() {
        return Err("fixture child did not complete the stream".into());
    }
    if let Some(batch) = batcher.flush() {
        publish(batch)?;
    }
    if published_batches >= input_deltas {
        return Err("fixture did not coalesce stream text".into());
    }
    if !state.publish_stream(workspace, StreamChange::Completed) {
        return Err("fixture stream lost its workspace".into());
    }
    Ok(())
}

#[tauri::command]
pub fn verification_mode(verification: State<'_, Verification>) -> Verification {
    *verification
}

#[tauri::command]
pub fn verify_fixture_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    scope_verified: bool,
    subscription_verified: bool,
    stream_recovered: bool,
    items: Vec<TranscriptItem>,
    rendered: String,
) -> Result<(), String> {
    if *verification != Verification::Streaming {
        return Err("fixture verification was not requested at launch".into());
    }
    if !scope_verified {
        eprintln!("Workspace IPC did not return the expected error for an unknown grant");
        app.exit(1);
        return Ok(());
    }
    if !subscription_verified {
        eprintln!(
            "Workspace subscription did not recover the complete revision after a gap and reload"
        );
        app.exit(1);
        return Ok(());
    }
    let chunks = scenario().map_err(|error| error.to_string())?.chunks;
    let expected = [
        TranscriptItem {
            item_id: PRIMARY_ITEM.into(),
            text: chunks.concat(),
            completed: true,
        },
        TranscriptItem {
            item_id: SECONDARY_ITEM.into(),
            text: SECONDARY_TEXT.concat(),
            completed: true,
        },
    ];
    let expected_text = expected
        .iter()
        .map(|item| item.text.as_str())
        .collect::<String>();
    if !stream_recovered || items != expected || rendered != expected_text {
        eprintln!("WebView fixture differed from the expected ordered Unicode output");
        app.exit(1);
        return Ok(());
    }
    println!("Verified workspace grant rejection and revision recovery across WebView reload");
    println!(
        "Verified {} ordered fixture deltas and exact WebView text",
        chunks.len() + SECONDARY_TEXT.len()
    );
    println!(
        "Verified item batching, terminal ordering, and exact transcript recovery across reconnect"
    );
    app.exit(0);
    Ok(())
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaEvidence {
    secure_context: bool,
    capture_api: bool,
    playback_api: bool,
    peer_api: bool,
    negotiated_sessions: u8,
    failure: Option<String>,
}

#[tauri::command]
pub fn verify_media_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    evidence: MediaEvidence,
) -> Result<(), String> {
    if *verification != Verification::Media {
        return Err("media verification was not requested at launch".into());
    }
    let negotiation = if evidence.peer_api {
        evidence.negotiated_sessions == 2
    } else {
        cfg!(target_os = "linux") && evidence.negotiated_sessions == 0
    };
    let passed = evidence.secure_context
        && evidence.capture_api
        && evidence.playback_api
        && evidence.failure.is_none()
        && negotiation;
    println!("WebView media evidence: {}", json!(evidence));
    app.exit(i32::from(!passed));
    Ok(())
}
