use std::{
    env,
    io::{self, Write},
    process::Stdio,
    time::Duration,
};

use codex_gui_core::codex::{JsonlReader, ServerEvent, ServerMessage, read_message};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tauri::{AppHandle, State, ipc::Channel};
use tokio::process::Command;

pub const CHILD_ARGUMENT: &str = "--diagnostic-fixture-stdio";
const STREAMING_SCENARIO: &str =
    include_str!("../../../Tests/E2E/MockBackend/mock_backend/scenarios/streaming.json");

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
    for text in scenario()?.chunks {
        let message = json!({
            "method": "item/agentMessage/delta",
            "params": {"delta": text},
        });
        serde_json::to_writer(&mut stdout, &message)?;
        stdout.write_all(b"\n")?;
        stdout.flush()?;
        std::thread::sleep(Duration::from_millis(40));
    }
    Ok(())
}

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum StreamMessage {
    Delta { text: String },
    Complete,
}

#[tauri::command]
pub async fn stream_fixture(output: Channel<StreamMessage>) -> Result<(), String> {
    let result = tokio::time::timeout(Duration::from_secs(15), send_fixture(&output))
        .await
        .map_err(|_| "fixture timed out".to_string())?;
    result.map_err(|error| error.to_string())
}

async fn send_fixture(
    output: &Channel<StreamMessage>,
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
    while let Some(message) = read_message(&mut reader).await? {
        let ServerMessage::Event(ServerEvent::Notification { method, params }) = message else {
            return Err("fixture sent an unexpected envelope".into());
        };
        if method != "item/agentMessage/delta" {
            return Err("fixture sent an unexpected notification".into());
        }
        let text = params["delta"]
            .as_str()
            .ok_or("fixture sent an invalid delta")?;
        output.send(StreamMessage::Delta {
            text: text.to_owned(),
        })?;
    }
    if !child.wait().await?.success() {
        return Err("fixture child exited unsuccessfully".into());
    }
    output.send(StreamMessage::Complete)?;
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
    deltas: Vec<String>,
    rendered: String,
) -> Result<(), String> {
    if *verification != Verification::Streaming {
        return Err("fixture verification was not requested at launch".into());
    }
    let expected = scenario().map_err(|error| error.to_string())?.chunks;
    if deltas != expected || rendered != expected.concat() {
        eprintln!("WebView fixture differed from the expected ordered Unicode output");
        app.exit(1);
        return Ok(());
    }
    println!(
        "Verified {} ordered fixture deltas and exact WebView text",
        expected.len()
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
    let passed = evidence.secure_context
        && evidence.capture_api
        && evidence.playback_api
        && evidence.peer_api
        && evidence.negotiated_sessions == 2
        && evidence.failure.is_none();
    println!("WebView media evidence: {}", json!(evidence));
    app.exit(i32::from(!passed));
    Ok(())
}
