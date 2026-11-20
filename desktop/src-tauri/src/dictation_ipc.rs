use std::{
    error::Error,
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender},
    },
    time::Duration,
};

use codex_gui_core::ipc::{DictationEvent, DictationTarget, IpcError};
use tauri::{AppHandle, Manager, State, WebviewWindow, ipc::Channel, path::BaseDirectory};
use uuid::Uuid;

use crate::{
    fixture::Verification,
    project_ipc::{ProjectIpc, authorize_view},
};

mod audio;

type Failure = Box<dyn Error + Send + Sync>;
type Result<T> = std::result::Result<T, Failure>;
const MAX_RECORDING: Duration = Duration::from_secs(30);
const MODEL: &str = "voice-models/ggml-tiny-q5_1.bin";

#[derive(Default)]
pub struct QuestionDictation {
    current: Mutex<Option<Session>>,
    fixture_started: AtomicBool,
}

struct Session {
    id: Uuid,
    target: DictationTarget,
    send: SyncSender<Control>,
    cancelled: Arc<AtomicBool>,
}

#[derive(Clone, Copy)]
enum Control {
    Finish,
    Cancel,
}

impl Drop for Session {
    fn drop(&mut self) {
        self.cancelled.store(true, Ordering::Relaxed);
        let _ = self.send.try_send(Control::Cancel);
    }
}

impl QuestionDictation {
    pub fn begin(
        &self,
        app: &AppHandle,
        id: Uuid,
        target: DictationTarget,
        events: Channel<DictationEvent>,
    ) {
        let (send, controls) = mpsc::sync_channel(1);
        let cancelled = Arc::new(AtomicBool::new(false));
        *self.current.lock().expect("dictation lock poisoned") = Some(Session {
            id,
            target,
            send: send.clone(),
            cancelled: cancelled.clone(),
        });
        let app = app.clone();
        tauri::async_runtime::spawn_blocking(move || {
            let outcome = transcribe(&app, &events, &controls, send, &cancelled);
            let mut current = app
                .state::<Self>()
                .inner()
                .current
                .lock()
                .expect("dictation lock poisoned");
            let event = match outcome {
                Ok(text) if current.as_ref().is_some_and(|session| session.id == id) => {
                    DictationEvent::Finished { text }
                }
                _ => DictationEvent::Retired,
            };
            if current.as_ref().is_some_and(|session| session.id == id) {
                *current = None;
            }
            let _ = events.send(event);
        });
    }

    pub fn retain(&self, authorized: impl FnOnce(&DictationTarget) -> bool) {
        let mut current = self.current.lock().expect("dictation lock poisoned");
        if current
            .as_ref()
            .is_some_and(|session| !authorized(&session.target))
        {
            *current = None;
        }
    }
}

#[tauri::command]
pub async fn start_question_dictation(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    target: DictationTarget,
    id: Uuid,
    events: Channel<DictationEvent>,
) -> std::result::Result<(), IpcError> {
    authorize_view(&window)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    navigation
        .start_question_dictation(target, id, events)
        .await
}

#[tauri::command]
pub fn end_question_dictation(
    window: WebviewWindow,
    state: State<'_, QuestionDictation>,
    id: Uuid,
    cancel: bool,
) -> std::result::Result<(), IpcError> {
    authorize_view(&window)?;
    let mut current = state.current.lock().expect("dictation lock poisoned");
    if let Some(session) = current.as_ref().filter(|session| session.id == id) {
        if cancel {
            *current = None;
        } else {
            let _ = session.send.try_send(Control::Finish);
        }
    }
    Ok(())
}

fn transcribe(
    app: &AppHandle,
    events: &Channel<DictationEvent>,
    controls: &Receiver<Control>,
    send: SyncSender<Control>,
    cancelled: &AtomicBool,
) -> Result<String> {
    let model = app.path().resolve(MODEL, BaseDirectory::Resource)?;
    if !model.is_file() || cancelled.load(Ordering::Relaxed) {
        return Err("Dictation session is unavailable".into());
    }
    let samples = if *app.state::<Verification>() == Verification::QuestionDictation {
        if !app
            .state::<QuestionDictation>()
            .fixture_started
            .swap(true, Ordering::Relaxed)
        {
            return Err("Fixture microphone permission denied".into());
        }
        fixture_capture(events, controls)?
    } else {
        audio::record(events, controls, send)?
    };
    if cancelled.load(Ordering::Relaxed) {
        return Err("Dictation session was retired".into());
    }
    recognize(&model, &samples, cancelled)
}

fn fixture_capture(
    events: &Channel<DictationEvent>,
    controls: &Receiver<Control>,
) -> Result<Vec<f32>> {
    let path = std::env::var_os("CODEX_GUI_QA_DICTATION_PCM").ok_or("Missing fixture PCM")?;
    let bytes = std::fs::read(path)?;
    if bytes.len() > 2 * audio::RECOGNIZER_RATE as usize * MAX_RECORDING.as_secs() as usize
        || bytes.len() % 2 != 0
    {
        return Err("Invalid fixture PCM".into());
    }
    events.send(DictationEvent::Started)?;
    if !matches!(controls.recv_timeout(MAX_RECORDING), Ok(Control::Finish)) {
        return Err("Fixture capture was retired".into());
    }
    Ok(bytes
        .chunks_exact(2)
        .map(|frame| f32::from(i16::from_le_bytes([frame[0], frame[1]])) / 32768.0)
        .collect())
}

fn recognize(model: &Path, samples: &[f32], cancelled: &AtomicBool) -> Result<String> {
    use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

    if !samples.iter().any(|sample| sample.abs() > 0.002) {
        return Ok(String::new());
    }
    let mut config = WhisperContextParameters::default();
    config.use_gpu(false);
    let context = WhisperContext::new_with_params(model, config)?;
    let mut state = context.create_state()?;
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    let threads = std::thread::available_parallelism().map_or(1, |cores| cores.get().min(4));
    params.set_n_threads(threads as i32);
    params.set_language(None);
    params.set_no_timestamps(true);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    unsafe extern "C" fn abort(data: *mut std::ffi::c_void) -> bool {
        // The caller borrows this flag for the duration of the synchronous decoder call.
        unsafe { &*data.cast::<AtomicBool>() }.load(Ordering::Relaxed)
    }
    // The decoder uses the callback only inside `full`, while `cancelled` is borrowed.
    unsafe {
        params.set_abort_callback(Some(abort));
        params.set_abort_callback_user_data(std::ptr::from_ref(cancelled).cast_mut().cast());
    }
    state.full(params, samples)?;
    let mut text = String::new();
    for segment in state.as_iter() {
        let next = segment.to_str_lossy()?;
        if next.trim() != "[BLANK_AUDIO]" {
            text.push_str(&next);
        }
    }
    Ok(text.trim().to_owned())
}
