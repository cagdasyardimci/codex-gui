use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
};

use codex_gui_core::ipc::{
    IpcError, WorkspaceGrants, WorkspaceId, WorkspaceRequest, WorkspaceView, authorize_window,
};
use tauri::{Config, Manager, State, Url, WebviewWindow};
use tauri_plugin_dialog::DialogExt;
use tokio::sync::oneshot;

#[derive(Default)]
pub struct ProjectIpc {
    grants: Mutex<WorkspaceGrants>,
    picking: AtomicBool,
}

struct Picker<'a>(&'a AtomicBool);

impl Drop for Picker<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

impl ProjectIpc {
    fn reserve_picker(&self) -> Result<Picker<'_>, IpcError> {
        self.picking
            .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
            .map_err(|_| IpcError::PickerBusy)?;
        Ok(Picker(&self.picking))
    }
}

pub fn app_location(config: &Config, use_https: bool) -> Url {
    if tauri::is_dev()
        && let Some(dev_url) = &config.build.dev_url
    {
        return dev_url.clone();
    }
    let base = if cfg!(target_os = "windows") {
        if use_https {
            "https://tauri.localhost/"
        } else {
            "http://tauri.localhost/"
        }
    } else {
        "tauri://localhost"
    };
    Url::parse(base).expect("static desktop origin")
}

pub fn allows_navigation(base: &Url, destination: &Url) -> bool {
    destination.scheme() == base.scheme()
        && destination.host_str() == base.host_str()
        && destination.port_or_known_default() == base.port_or_known_default()
        && destination.username().is_empty()
        && destination.password().is_none()
        && destination.query().is_none()
        && matches!(destination.path(), "" | "/" | "/index.html")
}

fn authorize_view(window: &WebviewWindow) -> Result<(), IpcError> {
    authorize_window(window.label())?;
    let config = window.app_handle().config();
    let main = config
        .app
        .windows
        .iter()
        .find(|item| item.label == window.label())
        .ok_or(IpcError::UnauthorizedWindow)?;
    let here = window.url().map_err(|_| IpcError::UnauthorizedWindow)?;
    if !allows_navigation(&app_location(config, main.use_https_scheme), &here) {
        return Err(IpcError::UnauthorizedWindow);
    }
    Ok(())
}

#[tauri::command]
pub async fn pick_workspace(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
) -> Result<Option<WorkspaceId>, IpcError> {
    authorize_view(&window)?;
    let _picker = state.reserve_picker()?;
    let (picked, selection) = oneshot::channel();
    window
        .dialog()
        .file()
        .set_parent(&window)
        .set_title("Open Project")
        .pick_folder(move |result| {
            let _ = picked.send(result);
        });
    let selected = selection.await.map_err(|_| IpcError::InvalidCheckout)?;
    let Some(selected) = selected else {
        return Ok(None);
    };
    authorize_view(&window)?;
    let folder = selected
        .into_path()
        .map_err(|_| IpcError::InvalidCheckout)?;
    state
        .grants
        .lock()
        .expect("workspace grants lock poisoned")
        .select_folder(window.label(), &folder)
        .map(Some)
}

#[tauri::command]
pub fn workspace_snapshot(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: WorkspaceRequest,
) -> Result<WorkspaceView, IpcError> {
    authorize_view(&window)?;
    state
        .grants
        .lock()
        .expect("workspace grants lock poisoned")
        .snapshot(window.label(), request)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn navigation_requires_the_exact_asset_or_development_entrypoint() {
        for base in [
            "tauri://localhost",
            "http://tauri.localhost/",
            "http://127.0.0.1:1420/",
        ] {
            let base = Url::parse(base).unwrap();
            assert!(allows_navigation(&base, &base));
            assert!(allows_navigation(&base, &base.join("/index.html").unwrap()));
            for other in ["https://example.test/", "about:blank", "/other.html"] {
                assert!(!allows_navigation(&base, &base.join(other).unwrap()));
            }
        }
    }

    #[test]
    fn only_one_native_picker_can_own_the_selection() {
        let state = ProjectIpc::default();
        let active = state.reserve_picker().unwrap();
        assert!(matches!(state.reserve_picker(), Err(IpcError::PickerBusy)));
        drop(active);
        assert!(state.reserve_picker().is_ok());
    }
}
