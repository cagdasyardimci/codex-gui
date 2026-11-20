use std::{sync::Mutex, time::Duration};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable, ServerEvent},
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    ipc::{IpcError, SpeechAudio, SpeechEvent},
};
use tauri::{AppHandle, Manager, State, WebviewWindow, ipc::Channel};
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::project_ipc::authorize_view;

type SpeechResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;
const RPC_TIMEOUT: Duration = Duration::from_secs(8);
const SPEECH_TIMEOUT: Duration = Duration::from_secs(25);

#[derive(Default)]
pub struct SpeechPlayback {
    current: Mutex<Option<Playback>>,
}

struct Playback {
    owner: Uuid,
    id: Uuid,
    _cancel: oneshot::Sender<()>,
}

pub struct Speak {
    pub owner: Uuid,
    pub id: Uuid,
    pub checkout: CheckoutIdentity,
    pub voice: String,
    pub text: String,
    pub events: Channel<SpeechEvent>,
}

impl SpeechPlayback {
    pub fn begin(&self, app: &AppHandle, request: Speak) {
        let (cancel, retired) = oneshot::channel();
        let id = request.id;
        *self.current.lock().expect("speech lock poisoned") = Some(Playback {
            id,
            owner: request.owner,
            _cancel: cancel,
        });
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            play(request, retired).await;
            app.state::<SpeechPlayback>().retire(|entry| entry.id == id);
        });
    }

    pub fn retire_owner(&self, owner: Uuid) {
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
pub fn stop_speech(
    window: WebviewWindow,
    playback: State<'_, SpeechPlayback>,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    playback.retire(|entry| entry.id == id);
    Ok(())
}

async fn play(request: Speak, mut retired: oneshot::Receiver<()>) {
    let result = play_until_retired(&request, &mut retired).await;
    if let Err(error) = result {
        eprintln!("{error}");
        let _ = request.events.send(SpeechEvent::Retired);
    }
}

async fn play_until_retired(
    request: &Speak,
    retired: &mut oneshot::Receiver<()>,
) -> SpeechResult<()> {
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
        _ = &mut *retired => return Ok(()),
    };
    let browser = CodexBrowser::new(connection.client());
    let mut thread = None;
    let result = tokio::select! {
        result = tokio::time::timeout(SPEECH_TIMEOUT, stream(&mut connection, &browser, request, &mut thread)) =>
            result.map_err(|error| Box::new(error) as Box<dyn std::error::Error + Send + Sync>).and_then(|result| result),
        _ = &mut *retired => Ok(()),
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
) -> SpeechResult<()> {
    if !browser
        .speech_voice_available(&request.voice, RPC_TIMEOUT)
        .await?
    {
        return Err("Realtime speech is unavailable for the captured provider".into());
    }
    let thread = browser.create_speech_thread(RPC_TIMEOUT).await?;
    *opened = Some(thread.clone());
    browser
        .start_speech(&thread, request.id, &request.voice, RPC_TIMEOUT)
        .await?;
    let mut ready = false;
    let mut received = false;
    let mut frames: u64 = 0;
    while let Some(event) = connection.next_event().await {
        let ServerEvent::Notification { method, params } = event else {
            return Err("Unexpected interactive request during standalone speech".into());
        };
        if params["threadId"].as_str() != Some(thread.0.as_str()) {
            continue;
        }
        match method.as_str() {
            "thread/realtime/started"
                if !ready
                    && params["version"] == "v3"
                    && params["realtimeSessionId"]
                        .as_str()
                        .is_none_or(|value| Uuid::parse_str(value).ok() == Some(request.id)) =>
            {
                ready = true;
                browser
                    .append_speech(&thread, &request.text, RPC_TIMEOUT)
                    .await?;
            }
            "thread/realtime/outputAudio/delta" if ready => {
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
            "thread/realtime/transcript/done" if ready && params["role"] == "assistant" => {
                if !received {
                    return Err("Standalone speech returned no audio".into());
                }
                request.events.send(SpeechEvent::Finished)?;
                return Ok(());
            }
            "thread/realtime/closed" | "thread/realtime/error" => break,
            "thread/realtime/itemAdded" if params["item"]["type"] == "handoff_request" => break,
            _ => {}
        }
    }
    Err("Standalone speech ended before playback completed".into())
}
