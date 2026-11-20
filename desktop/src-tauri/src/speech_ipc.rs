use std::{sync::Mutex, time::Duration};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable, ServerEvent},
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    ipc::{IpcError, SpeechAudio, SpeechEvent, TranscriptRowRequest, WorkspaceId},
};
use pulldown_cmark::{Event, TagEnd};
use tauri::{AppHandle, Manager, State, WebviewWindow, ipc::Channel};
use tokio::sync::{oneshot, watch};
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

type SpeechResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;
const RPC_TIMEOUT: Duration = Duration::from_secs(8);
const SPEECH_TIMEOUT: Duration = Duration::from_secs(60);
pub(crate) const MAX_TEXT_BYTES: usize = 256 * 1024;
const SEGMENT_BYTES: usize = 400;

#[derive(Default)]
pub struct SpeechPlayback {
    current: Mutex<Option<Playback>>,
}

struct Playback {
    owner: SpeechOwner,
    id: Uuid,
    drained: watch::Sender<u32>,
    _cancel: oneshot::Sender<()>,
}

#[derive(Clone, Copy, PartialEq)]
pub enum SpeechOwner {
    Settings(Uuid),
    Transcript,
}

pub struct Speak {
    pub owner: SpeechOwner,
    pub id: Uuid,
    pub checkout: CheckoutIdentity,
    pub voice: Option<String>,
    pub text: String,
    pub events: Channel<SpeechEvent>,
}

impl SpeechPlayback {
    pub fn begin(&self, app: &AppHandle, request: Speak) {
        let (cancel, retired) = oneshot::channel();
        let (drained, drain) = watch::channel(0);
        let id = request.id;
        *self.current.lock().expect("speech lock poisoned") = Some(Playback {
            id,
            owner: request.owner,
            drained,
            _cancel: cancel,
        });
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            play(request, retired, drain).await;
            app.state::<SpeechPlayback>().retire(|entry| entry.id == id);
        });
    }

    pub fn retire_owner(&self, owner: SpeechOwner) {
        self.retire(|playback| playback.owner == owner);
    }

    fn retire(&self, matches: impl FnOnce(&Playback) -> bool) {
        let mut current = self.current.lock().expect("speech lock poisoned");
        if current.as_ref().is_some_and(matches) {
            *current = None;
        }
    }
}

#[tauri::command]
pub async fn can_read_aloud(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    workspace_id: WorkspaceId,
) -> Result<bool, IpcError> {
    authorize_view(&window)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    let client = navigation.speech_client(workspace_id).await?;
    let available = CodexBrowser::new(client)
        .speech_voice_available(None, RPC_TIMEOUT)
        .await
        .unwrap_or(false);
    Ok(available)
}

#[tauri::command]
pub async fn read_aloud(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    row: TranscriptRowRequest,
    id: Uuid,
    events: Channel<SpeechEvent>,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    navigation.read_aloud(row, id, events).await
}

pub(crate) fn response_text(markdown: &str) -> Result<String, IpcError> {
    if markdown.len() > MAX_TEXT_BYTES {
        return Err(IpcError::StaleSelection);
    }
    let mut plain = String::with_capacity(markdown.len());
    for event in crate::transcript_ipc::markdown_events(markdown) {
        match event {
            Event::Text(text)
            | Event::Code(text)
            | Event::InlineMath(text)
            | Event::DisplayMath(text) => plain.push_str(&text),
            Event::SoftBreak
            | Event::HardBreak
            | Event::Rule
            | Event::End(
                TagEnd::Paragraph
                | TagEnd::Heading(_)
                | TagEnd::CodeBlock
                | TagEnd::Item
                | TagEnd::TableRow,
            ) => plain.push('\n'),
            Event::End(TagEnd::TableCell) => plain.push(' '),
            _ => {}
        }
    }
    let text = plain.trim();
    if text.is_empty() || text.len() > MAX_TEXT_BYTES {
        return Err(IpcError::StaleSelection);
    }
    Ok(text.to_owned())
}

#[tauri::command]
pub fn stop_speech(
    window: WebviewWindow,
    playback: State<'_, SpeechPlayback>,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    playback.retire(|entry| entry.id == id);
    Ok(())
}

#[tauri::command]
pub fn speech_segment_drained(
    window: WebviewWindow,
    playback: State<'_, SpeechPlayback>,
    id: Uuid,
    index: u32,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let current = playback.current.lock().expect("speech lock poisoned");
    if let Some(entry) = current.as_ref().filter(|entry| entry.id == id) {
        entry.drained.send_if_modified(|drained| {
            if drained.checked_add(1) != Some(index) {
                return false;
            }
            *drained = index;
            true
        });
    }
    Ok(())
}

async fn play(request: Speak, mut retired: oneshot::Receiver<()>, mut drain: watch::Receiver<u32>) {
    let event = match play_until_retired(&request, &mut retired, &mut drain).await {
        Ok(true) => SpeechEvent::Finished,
        Ok(false) => SpeechEvent::Retired,
        Err(error) => {
            eprintln!("{error}");
            SpeechEvent::Retired
        }
    };
    let _ = request.events.send(event);
}

async fn play_until_retired(
    request: &Speak,
    retired: &mut oneshot::Receiver<()>,
    drain: &mut watch::Receiver<u32>,
) -> SpeechResult<bool> {
    request.checkout.revalidate()?;
    let executable = CodexExecutable::discover(None)?;
    let identity = ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::new_v4()),
            checkout: Some(request.checkout.clone()),
        },
        generation: ConnectionGeneration(1),
    };
    let opening = AppServerConnection::connect(
        &executable,
        identity,
        ClientInfo {
            name: "codex_gui_speech",
            title: "Codex GUI Speech",
            version: env!("CARGO_PKG_VERSION"),
        },
        RPC_TIMEOUT,
    );
    let mut connection = tokio::select! {
        result = opening => result?,
        _ = &mut *retired => return Ok(false),
    };
    let browser = CodexBrowser::new(connection.client());
    let mut thread = None;
    let result = tokio::select! {
        result = stream(&mut connection, &browser, request, &mut thread, drain) => result.map(|()| true),
        _ = &mut *retired => Ok(false),
    };
    if let Some(thread) = thread {
        let _ = browser.stop_voice_call(&thread, RPC_TIMEOUT).await;
    }
    if let Err(error) = connection.disconnect().await {
        eprintln!("{error}");
    }
    result
}

async fn stream(
    connection: &mut AppServerConnection,
    browser: &CodexBrowser,
    request: &Speak,
    opened: &mut Option<ThreadId>,
    drain: &mut watch::Receiver<u32>,
) -> SpeechResult<()> {
    if !browser
        .speech_voice_available(request.voice.as_deref(), RPC_TIMEOUT)
        .await?
    {
        return Err("Realtime speech is unavailable for the captured provider".into());
    }
    let thread = browser.create_speech_thread(RPC_TIMEOUT).await?;
    *opened = Some(thread.clone());
    browser
        .start_speech(&thread, request.id, request.voice.as_deref(), RPC_TIMEOUT)
        .await?;
    loop {
        let (method, params) = speech_event(connection, &thread).await?;
        if method == "thread/realtime/started"
            && params["version"] == "v3"
            && params["realtimeSessionId"]
                .as_str()
                .is_none_or(|value| Uuid::parse_str(value).ok() == Some(request.id))
        {
            break;
        }
    }
    for (index, text) in segments(&request.text).enumerate() {
        browser.append_speech(&thread, text, RPC_TIMEOUT).await?;
        stream_segment(connection, &thread, request).await?;
        let index = index as u32 + 1;
        request
            .events
            .send(SpeechEvent::SegmentFinished { index })?;
        tokio::time::timeout(SPEECH_TIMEOUT, drain.wait_for(|value| *value >= index)).await??;
    }
    Ok(())
}

fn segments(mut rest: &str) -> impl Iterator<Item = &str> {
    std::iter::from_fn(move || {
        if rest.is_empty() {
            return None;
        }
        let mut end = rest.floor_char_boundary(SEGMENT_BYTES.min(rest.len()));
        if end < rest.len()
            && let Some((at, character)) = rest[..end].rmatch_indices(char::is_whitespace).next()
            && at >= end / 2
        {
            end = at + character.len();
        }
        let (part, tail) = rest.split_at(end);
        rest = tail;
        Some(part)
    })
}

async fn speech_event(
    connection: &mut AppServerConnection,
    thread: &ThreadId,
) -> SpeechResult<(String, serde_json::Value)> {
    while let Some(event) = tokio::time::timeout(SPEECH_TIMEOUT, connection.next_event()).await? {
        let ServerEvent::Notification { method, params } = event else {
            return Err("Unexpected interactive request during standalone speech".into());
        };
        if params["threadId"].as_str() != Some(thread.0.as_str()) {
            continue;
        }
        if matches!(
            method.as_str(),
            "thread/realtime/closed" | "thread/realtime/error"
        ) || method == "thread/realtime/itemAdded" && params["item"]["type"] == "handoff_request"
        {
            break;
        }
        return Ok((method, params));
    }
    Err("Standalone speech ended before playback completed".into())
}

async fn stream_segment(
    connection: &mut AppServerConnection,
    thread: &ThreadId,
    request: &Speak,
) -> SpeechResult<()> {
    let mut received = false;
    let mut frames: u64 = 0;
    loop {
        let (method, params) = speech_event(connection, thread).await?;
        match method.as_str() {
            "thread/realtime/outputAudio/delta" => {
                let audio: SpeechAudio = serde_json::from_value(params["audio"].clone())?;
                if audio.data.is_empty() {
                    continue;
                }
                if !audio.valid() || frames >= 1024 {
                    return Err("Invalid standalone speech audio".into());
                }
                frames += 1;
                received = true;
                request.events.send(SpeechEvent::Audio { audio })?;
            }
            "thread/realtime/transcript/done" if params["role"] == "assistant" => {
                if !received {
                    return Err("Standalone speech returned no audio".into());
                }
                return Ok(());
            }
            _ => {}
        }
    }
}
