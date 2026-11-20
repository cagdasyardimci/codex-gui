use codex_gui_core::{
    codex::voice_sample,
    ipc::{PreviewVoice, SpeechEvent},
};
use tauri::ipc::Channel;

use crate::speech_ipc::{Speak, SpeechPlayback};

use super::*;

#[tauri::command]
pub async fn preview_voice(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    request: PreviewVoice,
    events: Channel<SpeechEvent>,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let owner = request.selection.session;
    let selected = settings.selected.lock().expect("settings lock poisoned");
    let published = selected
        .as_ref()
        .filter(|session| session.id == owner)
        .and_then(|session| session.snapshot.as_ref())
        .filter(|snapshot| snapshot.revision == request.selection.revision)
        .ok_or(IpcError::StaleSelection)?;
    let voice = published
        .authority
        .configuration
        .voice(published.authority.account.account.as_ref());
    if !voice.is_some_and(|voice| {
        voice.preview && voice.voices.iter().any(|entry| entry.id == request.voice)
    }) {
        return Err(IpcError::StaleSelection);
    }
    let checkout = match request.workspace_id {
        Some(workspace) => project.checkout(window.label(), workspace)?,
        None => published.home.clone().ok_or(IpcError::ProjectUnavailable)?,
    };
    let text = voice_sample(&request.voice).to_owned();
    window.state::<SpeechPlayback>().begin(
        window.app_handle(),
        Speak {
            owner: crate::speech_ipc::SpeechOwner::Settings(owner),
            id: request.id,
            checkout,
            voice: Some(request.voice),
            text,
            events,
        },
    );
    Ok(())
}
