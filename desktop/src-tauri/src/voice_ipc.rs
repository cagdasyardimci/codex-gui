use std::{
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
    time::Duration,
};

use codex_gui_core::{
    codex::{AppServerClient, BrowseError, CodexBrowser, ServerEvent, validate_voice_sdp},
    identity::{ConnectionIdentity, ThreadId},
    ipc::{
        IpcError, PrepareVoiceCall, StartVoiceCall, VoiceCallUpdate, VoiceCallView, VoiceMediaHost,
        VoiceMute, VoicePhase,
    },
};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

#[cfg(target_os = "linux")]
mod native;

const EVENT: &str = "desktop:voice";
const TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Default)]
pub struct VoiceIpc {
    current: Mutex<Option<Call>>,
    lifecycle: tokio::sync::Mutex<()>,
}

struct Call {
    view: VoiceCallView,
    owner: AppServerClient,
    thread: ThreadId,
    voice: Option<String>,
    answer: Option<String>,
    entered_backend: bool,
    started: bool,
    media_ready: bool,
    opening_media: bool,
    text_pending: bool,
    #[cfg(target_os = "linux")]
    peer: Option<std::sync::Arc<native::NativePeer>>,
    #[cfg(target_os = "linux")]
    opening: Option<tokio::sync::oneshot::Sender<()>>,
}

impl VoiceIpc {
    pub fn available(&self) -> bool {
        self.current.lock().expect("voice lock poisoned").is_none()
    }

    pub fn owns_connection(&self, owner: &ConnectionIdentity) -> bool {
        self.current
            .lock()
            .expect("voice lock poisoned")
            .as_ref()
            .is_some_and(|call| call.owner.identity() == owner)
    }

    pub fn reserve(
        &self,
        app: &AppHandle,
        client: AppServerClient,
        thread: ThreadId,
        project: String,
        voice: Option<String>,
    ) -> Result<VoiceCallView, IpcError> {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if current.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let view = VoiceCallView {
            id: Uuid::new_v4(),
            project_id: project,
            chat_id: thread.0.clone(),
            media: if cfg!(target_os = "linux") {
                VoiceMediaHost::Native
            } else {
                VoiceMediaHost::Webview
            },
            phase: VoicePhase::Preparing,
            microphone_muted: false,
            speaker_muted: false,
        };
        *current = Some(Call {
            view: view.clone(),
            owner: client,
            thread,
            voice,
            answer: None,
            entered_backend: false,
            started: false,
            media_ready: false,
            opening_media: false,
            text_pending: false,
            #[cfg(target_os = "linux")]
            peer: None,
            #[cfg(target_os = "linux")]
            opening: None,
        });
        publish(app, &current);
        Ok(view)
    }

    pub fn begin_text(
        &self,
        owner: &ConnectionIdentity,
        chat: &str,
    ) -> Result<Option<Uuid>, IpcError> {
        let mut current = self.current.lock().expect("voice lock poisoned");
        let Some(call) = current
            .as_mut()
            .filter(|call| call.owner.identity() == owner && call.thread.0 == chat)
        else {
            return Ok(None);
        };
        if call.view.phase != VoicePhase::Active || call.text_pending {
            return Err(IpcError::StaleSelection);
        }
        call.text_pending = true;
        Ok(Some(call.view.id))
    }

    pub async fn append_text(&self, id: Uuid, text: &str) -> Result<(), IpcError> {
        let _gate = self.lifecycle.lock().await;
        let (client, thread) = {
            let mut current = self.current.lock().expect("voice lock poisoned");
            let call = selected(&mut current, id)?;
            if call.view.phase != VoicePhase::Active || !call.text_pending {
                return Err(IpcError::StaleSelection);
            }
            (call.owner.clone(), call.thread.clone())
        };
        CodexBrowser::new(client)
            .append_voice_text(&thread, text, TIMEOUT)
            .await
            .map_err(report)
    }

    pub fn finish_text(&self, id: Uuid) {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if let Ok(call) = selected(&mut current, id) {
            call.text_pending = false;
        }
    }

    fn retire(&self, app: &AppHandle, id: Uuid) {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if current.as_ref().is_some_and(|call| call.view.id == id) {
            #[cfg(target_os = "linux")]
            if let Some(call) = current.as_mut() {
                call.close_media();
            }
            *current = None;
            publish(app, &current);
        }
    }

    pub fn connection_closed(&self, app: &AppHandle, owner: &ConnectionIdentity) {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if current
            .as_ref()
            .is_some_and(|call| call.owner.identity() == owner)
        {
            #[cfg(target_os = "linux")]
            if let Some(call) = current.as_mut() {
                call.close_media();
            }
            *current = None;
            publish(app, &current);
        }
    }

    pub fn observe(
        &self,
        app: &AppHandle,
        owner: &ConnectionIdentity,
        event: &ServerEvent,
    ) -> bool {
        let ServerEvent::Notification { method, params } = event else {
            return false;
        };
        if !matches!(
            method.as_str(),
            "thread/realtime/started"
                | "thread/realtime/sdp"
                | "thread/realtime/closed"
                | "thread/realtime/error"
        ) {
            return false;
        }
        let mut current = self.current.lock().expect("voice lock poisoned");
        let Some(call) = current.as_mut().filter(|call| {
            call.owner.identity() == owner
                && params["threadId"].as_str() == Some(&call.thread.0)
                && call.entered_backend
        }) else {
            return true;
        };
        match method.as_str() {
            "thread/realtime/closed" => {
                #[cfg(target_os = "linux")]
                call.close_media();
                *current = None;
            }
            "thread/realtime/error" => {
                call.view.phase = VoicePhase::Ending;
                call.answer = None;
                #[cfg(target_os = "linux")]
                call.close_media();
            }
            "thread/realtime/started"
                if call.view.phase == VoicePhase::Connecting
                    && params["version"] == "v3"
                    && params["realtimeSessionId"].as_str().is_none_or(|value| {
                        Uuid::parse_str(value).is_ok_and(|id| id == call.view.id)
                    }) =>
            {
                call.started = true;
                call.try_activate();
            }
            "thread/realtime/sdp"
                if call.view.phase == VoicePhase::Connecting && call.answer.is_none() =>
            {
                if let Some(sdp) = params["sdp"].as_str().filter(|sdp| validate_voice_sdp(sdp)) {
                    call.answer = Some(sdp.to_owned());
                    #[cfg(target_os = "linux")]
                    if let Some(peer) = call.peer.clone() {
                        let id = call.view.id;
                        let sdp = sdp.to_owned();
                        let app = app.clone();
                        tauri::async_runtime::spawn(async move {
                            let result = peer.accept_answer(&sdp).await;
                            let state = app.state::<VoiceIpc>();
                            if result.is_ok() {
                                let _ = state.media_ready(&app, id);
                            } else {
                                let _ = end_call(&app, &state, id).await;
                            }
                        });
                    }
                }
            }
            _ => return true,
        }
        publish(app, &current);
        true
    }

    fn media_ready(&self, app: &AppHandle, id: Uuid) -> Result<(), IpcError> {
        let mut current = self.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, id)?;
        if call.view.phase != VoicePhase::Connecting || call.answer.is_none() {
            return Err(IpcError::StaleSelection);
        }
        call.media_ready = true;
        call.try_activate();
        publish(app, &current);
        Ok(())
    }
}

impl Call {
    #[cfg(target_os = "linux")]
    fn close_media(&mut self) {
        if let Some(peer) = self.peer.take() {
            peer.close();
        }
    }

    fn try_activate(&mut self) {
        if self.started && self.media_ready {
            self.view.phase = VoicePhase::Active;
        }
    }
}

fn selected(current: &mut Option<Call>, id: Uuid) -> Result<&mut Call, IpcError> {
    current
        .as_mut()
        .filter(|call| call.view.id == id)
        .ok_or(IpcError::StaleSelection)
}

fn update(current: &Option<Call>) -> VoiceCallUpdate {
    VoiceCallUpdate {
        call: current.as_ref().map(|call| call.view.clone()),
        answer: current
            .as_ref()
            .filter(|call| call.view.media == VoiceMediaHost::Webview)
            .and_then(|call| call.answer.clone()),
    }
}

fn publish(app: &AppHandle, current: &Option<Call>) {
    if let Err(error) = app.emit(EVENT, update(current)) {
        eprintln!("{error}");
    }
}

#[tauri::command]
pub fn read_voice_call(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
) -> Result<VoiceCallUpdate, IpcError> {
    authorize_view(&window)?;
    Ok(update(&state.current.lock().expect("voice lock poisoned")))
}

#[tauri::command]
pub async fn prepare_voice_call(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: PrepareVoiceCall,
) -> Result<VoiceCallView, IpcError> {
    authorize_view(&window)?;
    project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?
        .prepare_voice(request)
        .await
}

#[tauri::command]
pub async fn start_voice_transport(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    request: StartVoiceCall,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let app = window.app_handle();
    let id = request.id;
    let host = {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, id)?;
        if call.view.phase != VoicePhase::Preparing || call.opening_media {
            return Err(IpcError::StaleSelection);
        }
        match (call.view.media, &request.offer) {
            (VoiceMediaHost::Webview, Some(offer)) if validate_voice_sdp(offer) => {}
            (VoiceMediaHost::Native, None) => {}
            _ => return Err(IpcError::StaleSelection),
        }
        call.opening_media = true;
        call.view.media
    };
    let offer = match host {
        VoiceMediaHost::Webview => request.offer.ok_or(IpcError::StaleSelection)?,
        VoiceMediaHost::Native => {
            #[cfg(target_os = "linux")]
            {
                let (cancel, stopped) = tokio::sync::oneshot::channel();
                {
                    let mut current = state.current.lock().expect("voice lock poisoned");
                    selected(&mut current, id)?.opening = Some(cancel);
                }
                let result = tokio::select! {
                    result = native::NativePeer::offer(app) => result,
                    _ = stopped => return Err(IpcError::StaleSelection),
                };
                let (peer, offer) = match result {
                    Ok(result) => result,
                    Err(error) => {
                        state.retire(app, id);
                        return Err(report(error));
                    }
                };
                let mut current = state.current.lock().expect("voice lock poisoned");
                let call = selected(&mut current, id)?;
                call.opening = None;
                peer.mute(true, call.view.microphone_muted);
                peer.mute(false, call.view.speaker_muted);
                call.peer = Some(peer);
                offer
            }
            #[cfg(not(target_os = "linux"))]
            return Err(IpcError::ProjectUnavailable);
        }
    };
    let gate = state.lifecycle.lock().await;
    let (client, thread, voice) = {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, id)?;
        if call.view.phase != VoicePhase::Preparing {
            return Err(IpcError::StaleSelection);
        }
        call.entered_backend = true;
        call.view.phase = VoicePhase::Connecting;
        let target = (call.owner.clone(), call.thread.clone(), call.voice.clone());
        publish(app, &current);
        target
    };
    let result = CodexBrowser::new(client)
        .start_voice_call(&thread, id, &offer, voice.as_deref(), TIMEOUT)
        .await;
    drop(gate);
    if let Err(error) = result {
        if matches!(&error, BrowseError::Request(error) if error.is_unsent()) {
            state.retire(app, id);
        } else {
            let _ = end_call(app, &state, id).await;
        }
        return Err(report(error));
    }
    Ok(())
}

#[tauri::command]
pub fn voice_media_ready(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if cfg!(target_os = "linux") {
        return Err(IpcError::UnauthorizedWindow);
    }
    state.media_ready(window.app_handle(), id)
}

#[tauri::command]
pub fn set_voice_mute(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    request: VoiceMute,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let mut current = state.current.lock().expect("voice lock poisoned");
    let call = selected(&mut current, request.id)?;
    if call.view.phase == VoicePhase::Ending {
        return Err(IpcError::StaleSelection);
    }
    if request.microphone {
        call.view.microphone_muted = request.muted;
    } else {
        call.view.speaker_muted = request.muted;
    }
    #[cfg(target_os = "linux")]
    if let Some(peer) = &call.peer {
        peer.mute(request.microphone, request.muted);
    }
    publish(window.app_handle(), &current);
    Ok(())
}

#[tauri::command]
pub async fn end_voice_call(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    end_call(window.app_handle(), &state, id).await
}

async fn end_call(app: &AppHandle, state: &VoiceIpc, id: Uuid) -> Result<(), IpcError> {
    {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, id)?;
        if !call.entered_backend {
            *current = None;
            publish(app, &current);
            return Ok(());
        }
        call.view.phase = VoicePhase::Ending;
        call.answer = None;
        #[cfg(target_os = "linux")]
        call.close_media();
        publish(app, &current);
    }
    let _gate = state.lifecycle.lock().await;
    let (client, thread) = {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let Ok(call) = selected(&mut current, id) else {
            return Ok(());
        };
        (call.owner.clone(), call.thread.clone())
    };
    CodexBrowser::new(client)
        .stop_voice_call(&thread, TIMEOUT)
        .await
        .map_err(report)
}

fn fixture_root(window: &WebviewWindow) -> Result<PathBuf, IpcError> {
    authorize_view(window)?;
    if *window.state::<crate::fixture::Verification>() != crate::fixture::Verification::Voice {
        return Err(IpcError::UnauthorizedWindow);
    }
    crate::file_actions_ipc::fixture_data(window)
}

fn record_exchange(root: &Path, offer: &str, answer: &str) -> Result<(), IpcError> {
    if !validate_voice_sdp(offer) || !validate_voice_sdp(answer) {
        return Err(IpcError::StaleSelection);
    }
    let mut file = tempfile::NamedTempFile::new_in(root).map_err(report)?;
    write!(
        file,
        "{}",
        serde_json::json!({ "offer": offer, "answer": answer })
    )
    .map_err(report)?;
    file.persist(root.join("voice-exchange.json"))
        .map_err(report)?;
    Ok(())
}

#[tauri::command]
pub fn record_voice_fixture_exchange(
    window: WebviewWindow,
    offer: String,
    answer: String,
) -> Result<(), IpcError> {
    record_exchange(&fixture_root(&window)?, &offer, &answer)
}

#[tauri::command]
pub fn read_voice_fixture_media(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    id: Uuid,
) -> Result<serde_json::Value, IpcError> {
    fixture_root(&window)?;
    let mut current = state.current.lock().expect("voice lock poisoned");
    let call = selected(&mut current, id)?;
    #[cfg(target_os = "linux")]
    if let Some(peer) = &call.peer {
        return Ok(peer.fixture_media());
    }
    let _ = call;
    Err(IpcError::StaleSelection)
}

#[tauri::command]
pub fn verify_voice_result(
    window: WebviewWindow,
    failure: Option<String>,
    evidence: serde_json::Value,
) -> Result<(), IpcError> {
    fixture_root(&window)?;
    if let Some(failure) = failure {
        eprintln!("Voice verification failed: {failure}");
        window.app_handle().exit(1);
    } else {
        println!("Verified installed desktop voice: {evidence}");
        window.app_handle().exit(0);
    }
    Ok(())
}

fn report(error: impl std::fmt::Display) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
