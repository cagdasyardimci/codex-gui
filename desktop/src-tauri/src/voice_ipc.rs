use std::{
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
    time::Duration,
};

use codex_gui_core::{
    codex::{
        AppServerClient, BrowseError, CodexBrowser, RealtimeVoiceSelection, ServerEvent,
        validate_voice_sdp,
    },
    identity::{ConnectionIdentity, ThreadId},
    ipc::{
        IpcError, PrepareVoiceCall, SpeechAudio, StartVoiceCall, VoiceAudioUpdate, VoiceCallUpdate,
        VoiceCallView, VoiceMediaHost, VoiceMute, VoicePhase, VoiceReconnect,
    },
};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

#[cfg(target_os = "linux")]
mod native;

const EVENT: &str = "desktop:voice";
const AUDIO_EVENT: &str = "desktop:voice-audio";
const TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Default)]
pub struct VoiceIpc {
    current: Mutex<VoiceState>,
    lifecycle: tokio::sync::Mutex<()>,
}

#[derive(Default)]
struct VoiceState {
    call: Option<Call>,
    reconnect: Option<ResumeVoice>,
}

#[derive(Clone)]
pub struct ResumeVoice {
    view: VoiceReconnect,
    pub voice: Option<String>,
    microphone_muted: bool,
    speaker_muted: bool,
}

pub struct ReserveVoice {
    pub client: AppServerClient,
    pub thread: ThreadId,
    pub project: String,
    pub selection: RealtimeVoiceSelection,
    pub reconnect: Option<ResumeVoice>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Retirement {
    User,
    Reconnect,
    Fallback,
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
    fallback_allowed: bool,
    retirement: Option<Retirement>,
    #[cfg(target_os = "linux")]
    peer: Option<std::sync::Arc<native::NativePeer>>,
    #[cfg(target_os = "linux")]
    opening: Option<tokio::sync::oneshot::Sender<()>>,
}

impl VoiceIpc {
    pub fn available(&self) -> bool {
        self.current
            .lock()
            .expect("voice lock poisoned")
            .call
            .is_none()
    }

    pub fn owns_connection(&self, owner: &ConnectionIdentity) -> bool {
        self.current
            .lock()
            .expect("voice lock poisoned")
            .call
            .as_ref()
            .is_some_and(|call| call.owner.identity() == owner)
    }

    pub fn owns_chat(&self, owner: &ConnectionIdentity, chat: &str) -> bool {
        self.current
            .lock()
            .expect("voice lock poisoned")
            .call
            .as_ref()
            .is_some_and(|call| {
                call.owner.identity() == owner
                    && call.thread.0 == chat
                    && call.view.phase == VoicePhase::Active
            })
    }

    pub fn resume_target(
        &self,
        id: Uuid,
        project: &str,
        chat: Option<&str>,
    ) -> Result<ResumeVoice, IpcError> {
        self.current
            .lock()
            .expect("voice lock poisoned")
            .reconnect
            .as_ref()
            .filter(|target| {
                target.view.id == id
                    && target.view.project_id == project
                    && Some(target.view.chat_id.as_str()) == chat
            })
            .cloned()
            .ok_or(IpcError::StaleSelection)
    }

    pub fn reserve(
        &self,
        app: &AppHandle,
        request: ReserveVoice,
    ) -> Result<VoiceCallView, IpcError> {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if current.call.is_some()
            || request.reconnect.as_ref().is_some_and(|target| {
                current
                    .reconnect
                    .as_ref()
                    .is_none_or(|saved| saved.view != target.view)
            })
        {
            return Err(IpcError::StaleSelection);
        }
        let media = if !request.selection.web_rtc {
            VoiceMediaHost::Pcm
        } else if cfg!(target_os = "linux") {
            VoiceMediaHost::Native
        } else {
            VoiceMediaHost::Webview
        };
        let view = VoiceCallView {
            id: Uuid::new_v4(),
            project_id: request.project,
            chat_id: request.thread.0.clone(),
            media,
            phase: VoicePhase::Preparing,
            microphone_muted: request
                .reconnect
                .as_ref()
                .is_some_and(|target| target.microphone_muted),
            speaker_muted: request
                .reconnect
                .as_ref()
                .is_some_and(|target| target.speaker_muted),
        };
        current.reconnect = None;
        current.call = Some(Call::prepare(
            view.clone(),
            request.client,
            request.thread,
            request.selection.voice,
            media != VoiceMediaHost::Pcm && request.selection.web_socket,
        ));
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
            .call
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

    pub fn connection_closed(&self, app: &AppHandle, owner: &ConnectionIdentity) {
        let mut current = self.current.lock().expect("voice lock poisoned");
        if let Some(mut call) = current.call.take_if(|call| call.owner.identity() == owner) {
            if call.view.phase == VoicePhase::Active
                || call.retirement == Some(Retirement::Reconnect)
            {
                current.reconnect = Some(call.resume());
            }
            call.close_media();
            publish(app, &current);
        }
    }

    async fn failed(&self, app: &AppHandle, id: Uuid, unsent: bool) {
        let retirement = {
            let mut current = self.current.lock().expect("voice lock poisoned");
            let Ok(call) = selected(&mut current, id) else {
                return;
            };
            if call.retirement.is_some() {
                return;
            }
            if unsent {
                call.entered_backend = false;
            }
            if call.view.phase == VoicePhase::Active {
                Retirement::Reconnect
            } else if call.fallback_allowed {
                Retirement::Fallback
            } else {
                Retirement::User
            }
        };
        let _ = end_call(app, self, id, retirement).await;
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
                | "thread/realtime/outputAudio/delta"
        ) {
            return false;
        }
        let mut current = self.current.lock().expect("voice lock poisoned");
        let Some(call) = current.call.as_mut().filter(|call| {
            call.owner.identity() == owner
                && params["threadId"].as_str() == Some(&call.thread.0)
                && call.entered_backend
        }) else {
            return true;
        };
        match method.as_str() {
            "thread/realtime/closed" => {
                if let Some(mut ended) = current.call.take() {
                    ended.close_media();
                    match ended.retirement {
                        Some(Retirement::Fallback) => schedule_pcm(app, &mut current, ended),
                        Some(Retirement::Reconnect) => current.reconnect = Some(ended.resume()),
                        None if ended.view.phase == VoicePhase::Active => {
                            current.reconnect = Some(ended.resume())
                        }
                        None if ended.fallback_allowed => schedule_pcm(app, &mut current, ended),
                        _ => {}
                    }
                }
            }
            "thread/realtime/error" => {
                report_media_failure(app, call.view.id);
                return true;
            }
            "thread/realtime/outputAudio/delta"
                if call.view.phase == VoicePhase::Active
                    && call.view.media == VoiceMediaHost::Pcm =>
            {
                if let Ok(audio) = serde_json::from_value::<SpeechAudio>(params["audio"].clone())
                    && audio.valid()
                    && let Err(error) = app.emit(
                        AUDIO_EVENT,
                        VoiceAudioUpdate {
                            id: call.view.id,
                            audio,
                        },
                    )
                {
                    eprintln!("{error}");
                }
                return true;
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
                                if state.media_ready(&app, id).is_ok() {
                                    while peer.connected() {
                                        tokio::time::sleep(Duration::from_millis(300)).await;
                                    }
                                    state.failed(&app, id, false).await;
                                }
                            } else {
                                state.failed(&app, id, false).await;
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
    fn prepare(
        view: VoiceCallView,
        owner: AppServerClient,
        thread: ThreadId,
        voice: Option<String>,
        fallback_allowed: bool,
    ) -> Self {
        Self {
            view,
            owner,
            thread,
            voice,
            fallback_allowed,
            answer: None,
            entered_backend: false,
            started: false,
            media_ready: false,
            opening_media: false,
            text_pending: false,
            retirement: None,
            #[cfg(target_os = "linux")]
            peer: None,
            #[cfg(target_os = "linux")]
            opening: None,
        }
    }

    fn resume(&self) -> ResumeVoice {
        ResumeVoice {
            view: VoiceReconnect {
                id: self.view.id,
                project_id: self.view.project_id.clone(),
                chat_id: self.view.chat_id.clone(),
            },
            voice: self.voice.clone(),
            microphone_muted: self.view.microphone_muted,
            speaker_muted: self.view.speaker_muted,
        }
    }

    fn close_media(&mut self) {
        #[cfg(target_os = "linux")]
        {
            self.opening = None;
            if let Some(peer) = self.peer.take() {
                peer.close();
            }
        }
        self.answer = None;
    }

    fn try_activate(&mut self) {
        if self.started && self.media_ready {
            self.view.phase = VoicePhase::Active;
        }
    }
}

fn selected(current: &mut VoiceState, id: Uuid) -> Result<&mut Call, IpcError> {
    current
        .call
        .as_mut()
        .filter(|call| call.view.id == id)
        .ok_or(IpcError::StaleSelection)
}

fn update(current: &VoiceState) -> VoiceCallUpdate {
    VoiceCallUpdate {
        call: current.call.as_ref().map(|call| call.view.clone()),
        answer: current
            .call
            .as_ref()
            .filter(|call| call.view.media == VoiceMediaHost::Webview)
            .and_then(|call| call.answer.clone()),
        reconnect: current.reconnect.as_ref().map(|target| target.view.clone()),
    }
}

fn publish(app: &AppHandle, current: &VoiceState) {
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
            (VoiceMediaHost::Native | VoiceMediaHost::Pcm, None) => {}
            _ => return Err(IpcError::StaleSelection),
        }
        call.opening_media = true;
        call.view.media
    };
    let offer = match host {
        VoiceMediaHost::Webview => request.offer,
        VoiceMediaHost::Pcm => None,
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
                        state.failed(app, id, true).await;
                        return Err(report(error));
                    }
                };
                let mut current = state.current.lock().expect("voice lock poisoned");
                let call = selected(&mut current, id)?;
                call.opening = None;
                peer.mute(true, call.view.microphone_muted);
                peer.mute(false, call.view.speaker_muted);
                call.peer = Some(peer);
                Some(offer)
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
        call.media_ready = host == VoiceMediaHost::Pcm;
        call.view.phase = VoicePhase::Connecting;
        let target = (call.owner.clone(), call.thread.clone(), call.voice.clone());
        publish(app, &current);
        target
    };
    let result = CodexBrowser::new(client)
        .start_voice_call(&thread, id, offer.as_deref(), voice.as_deref(), TIMEOUT)
        .await;
    drop(gate);
    if let Err(error) = result {
        let unsent = matches!(&error, BrowseError::Request(error) if error.is_unsent());
        state.failed(app, id, unsent).await;
        return Err(report(error));
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(TIMEOUT).await;
        let state = app.state::<VoiceIpc>();
        let connecting = state
            .current
            .lock()
            .expect("voice lock poisoned")
            .call
            .as_ref()
            .is_some_and(|call| call.view.id == id && call.view.phase == VoicePhase::Connecting);
        if connecting {
            state.failed(&app, id, false).await;
        }
    });
    Ok(())
}

#[tauri::command]
pub async fn voice_media_failed(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    state.failed(window.app_handle(), id, false).await;
    Ok(())
}

#[tauri::command]
pub async fn append_voice_audio(
    window: WebviewWindow,
    state: State<'_, VoiceIpc>,
    update: VoiceAudioUpdate,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if update.audio.sample_rate != 24_000
        || update.audio.num_channels != 1
        || update.audio.data.len() > 24_000
        || !update.audio.valid()
    {
        return Err(IpcError::StaleSelection);
    }
    let _gate = state.lifecycle.lock().await;
    let (client, thread) = {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, update.id)?;
        if call.view.phase != VoicePhase::Active
            || call.view.media != VoiceMediaHost::Pcm
            || call.view.microphone_muted
        {
            return Err(IpcError::StaleSelection);
        }
        (call.owner.clone(), call.thread.clone())
    };
    CodexBrowser::new(client)
        .append_voice_audio(&thread, &update.audio, Duration::from_secs(2))
        .await
        .map_err(report)
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
    end_call(window.app_handle(), &state, id, Retirement::User).await
}

async fn end_call(
    app: &AppHandle,
    state: &VoiceIpc,
    id: Uuid,
    retirement: Retirement,
) -> Result<(), IpcError> {
    {
        let mut current = state.current.lock().expect("voice lock poisoned");
        let call = selected(&mut current, id)?;
        if call.retirement.is_some() && retirement != Retirement::User {
            return Ok(());
        }
        if !call.entered_backend {
            if let Some(mut ended) = current.call.take() {
                ended.close_media();
                if retirement == Retirement::Fallback {
                    schedule_pcm(app, &mut current, ended);
                }
            }
            publish(app, &current);
            return Ok(());
        }
        if call.retirement.is_some() {
            call.retirement = Some(Retirement::User);
            current.reconnect = None;
            publish(app, &current);
            return Ok(());
        }
        call.retirement = Some(retirement);
        call.view.phase = VoicePhase::Ending;
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

fn report_media_failure(app: &AppHandle, id: Uuid) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        app.state::<VoiceIpc>().failed(&app, id, false).await;
    });
}

fn schedule_pcm(app: &AppHandle, current: &mut VoiceState, mut ended: Call) {
    let id = ended.view.id;
    let client = ended.owner.clone();
    let selected_voice = ended.voice.clone();
    ended.entered_backend = false;
    ended.view.phase = VoicePhase::Ending;
    ended.retirement = Some(Retirement::Fallback);
    current.call = Some(ended);
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = app.state::<VoiceIpc>();
        let browser = CodexBrowser::new(client);
        let compatible = browser
            .voice_selection(selected_voice.as_deref(), TIMEOUT)
            .await
            .ok()
            .flatten()
            .is_some_and(|selection| selection.web_socket && selected_voice.is_some());
        let mut current = state.current.lock().expect("voice lock poisoned");
        let Some(ended) = current.call.take_if(|call| {
            call.view.id == id
                && call.retirement == Some(Retirement::Fallback)
                && !call.entered_backend
        }) else {
            return;
        };
        if compatible {
            let mut view = ended.view;
            view.id = Uuid::new_v4();
            view.media = VoiceMediaHost::Pcm;
            view.phase = VoicePhase::Preparing;
            current.call = Some(Call::prepare(
                view,
                ended.owner,
                ended.thread,
                ended.voice,
                false,
            ));
        }
        publish(&app, &current);
    });
}

fn fixture_root(window: &WebviewWindow) -> Result<PathBuf, IpcError> {
    authorize_view(window)?;
    if !matches!(
        *window.state::<crate::fixture::Verification>(),
        crate::fixture::Verification::Voice
            | crate::fixture::Verification::VoiceReconnect
            | crate::fixture::Verification::VoiceNoFallback
            | crate::fixture::Verification::VoiceHandoff
            | crate::fixture::Verification::VoiceHistory
            | crate::fixture::Verification::VoiceHistoryRestore
            | crate::fixture::Verification::ReadAloud
    ) {
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
pub fn trigger_voice_handoff(window: WebviewWindow) -> Result<(), IpcError> {
    if *window.state::<crate::fixture::Verification>() != crate::fixture::Verification::VoiceHandoff
    {
        return Err(IpcError::UnauthorizedWindow);
    }
    std::fs::write(fixture_root(&window)?.join("voice-handoff-trigger"), []).map_err(report)
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
