use std::sync::atomic::{AtomicBool, Ordering};

use codex_gui_core::ipc::IpcError;
use tauri::{AppHandle, Manager, State, WebviewWindow};

use crate::{
    fixture::Verification,
    project_ipc::{ProjectIpc, authorize_view},
};

pub const FIXTURE_APP_QUIT: i32 = 42;

#[derive(Default)]
pub struct QuitLifecycle(AtomicBool);

impl QuitLifecycle {
    pub fn allowed(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }

    pub fn allow_exit(&self) {
        self.0.store(true, Ordering::Release);
    }
}

pub fn handle_native_quit(app: &AppHandle) {
    let state = app.state::<ProjectIpc>();
    if let Some(navigation) = state.navigation.get().cloned() {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            if let Err(error) = navigation.request_quit(app).await {
                eprintln!("Could not begin desktop quit: {error:?}");
            }
        });
    }
}

#[tauri::command]
pub fn request_quit_fixture(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    application: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if !matches!(*verification, Verification::Quit | Verification::FileTools) {
        return Err(IpcError::UnauthorizedWindow);
    }
    if application {
        window.app_handle().exit(FIXTURE_APP_QUIT);
        return Ok(());
    }
    window.close().map_err(|_| IpcError::ProjectUnavailable)
}
