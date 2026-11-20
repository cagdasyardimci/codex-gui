use std::sync::{
    Arc, Mutex, OnceLock,
    atomic::{AtomicBool, Ordering},
};
use std::{path::Path, time::Duration};

use codex_gui_core::checkout::CheckoutIdentity;
use codex_gui_core::files::index::{ProjectPathMatch, WatchedProjectPaths};
use codex_gui_core::ipc::{
    IpcError, NavigationIntent, ProjectPathRequest, StreamChange, WorkspaceGrants, WorkspaceId,
    WorkspaceProjection, WorkspaceRequest, WorkspaceSubscription, WorkspaceUpdate,
    WorkspaceUpdateRequest, WorkspaceView, authorize_window,
};
use tauri::{Config, Manager, State, Url, WebviewWindow};
use tauri_plugin_dialog::DialogExt;
use tokio::sync::{Mutex as AsyncMutex, oneshot};

use crate::fixture::Verification;
use crate::navigation::NavigationHandle;

#[derive(Default)]
pub struct ProjectIpc {
    pub(crate) state: Arc<Mutex<ProjectState>>,
    pub(crate) navigation: OnceLock<NavigationHandle>,
    picking: AtomicBool,
    fixture_started: AtomicBool,
}

#[derive(Default)]
pub(crate) struct ProjectState {
    pub(crate) grants: WorkspaceGrants,
    pub(crate) projection: WorkspaceProjection,
    fixture_directory: Option<tempfile::TempDir>,
    file_index: Option<(WorkspaceId, Arc<AsyncMutex<WatchedProjectPaths>>)>,
    pub(crate) file_search: Option<Arc<crate::file_search_ipc::FileSearchSession>>,
    pub(crate) composer_catalog: Option<crate::composer_context_ipc::ComposerCatalog>,
}

impl ProjectState {
    pub(crate) fn retire_file_search(&mut self) {
        if let Some(search) = self.file_search.take() {
            search.cancel();
        }
    }

    fn select(&mut self, window: &str, folder: &Path) -> Result<WorkspaceId, IpcError> {
        let id = self.grants.select_folder(window, folder)?;
        self.publish();
        Ok(id)
    }

    pub(crate) fn publish(&mut self) {
        let view = self.grants.current_view();
        if self
            .file_index
            .as_ref()
            .is_some_and(|(owner, _)| view.as_ref().map(|view| view.workspace_id) != Some(*owner))
        {
            self.file_index = None;
        }
        self.projection.publish(view);
    }
}

pub(crate) struct Picker<'a>(&'a AtomicBool);

impl Drop for Picker<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

impl ProjectIpc {
    pub(crate) fn path_index(
        &self,
        window: &str,
        workspace: WorkspaceId,
    ) -> Result<Arc<AsyncMutex<WatchedProjectPaths>>, IpcError> {
        let mut state = self.state.lock().expect("workspace state lock poisoned");
        let checkout = state.grants.checkout(window, workspace)?;
        if state.file_index.as_ref().map(|(owner, _)| *owner) != Some(workspace) {
            state.file_index = Some((
                workspace,
                Arc::new(AsyncMutex::new(WatchedProjectPaths::new(checkout))),
            ));
        }
        Ok(state
            .file_index
            .as_ref()
            .expect("index for current grant")
            .1
            .clone())
    }

    pub(crate) fn checkout(
        &self,
        window: &str,
        workspace: WorkspaceId,
    ) -> Result<CheckoutIdentity, IpcError> {
        self.state
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .checkout(window, workspace)
    }
    pub(crate) fn reserve_picker(&self) -> Result<Picker<'_>, IpcError> {
        self.picking
            .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
            .map_err(|_| IpcError::PickerBusy)?;
        Ok(Picker(&self.picking))
    }

    pub fn start_fixture(&self, window: &WebviewWindow) -> Result<Option<WorkspaceId>, IpcError> {
        authorize_view(window)?;
        let workspace = self
            .state
            .lock()
            .expect("workspace state lock poisoned")
            .grants
            .current_view()
            .ok_or(IpcError::RetiredWorkspace)?
            .workspace_id;
        if self.fixture_started.swap(true, Ordering::AcqRel) {
            return Ok(None);
        }
        Ok(Some(workspace))
    }

    pub fn publish_stream(&self, workspace: WorkspaceId, change: StreamChange) -> bool {
        let mut state = self.state.lock().expect("workspace state lock poisoned");
        state.publish();
        state.projection.publish_stream(workspace, change)
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

pub(crate) fn authorize_view(window: &WebviewWindow) -> Result<(), IpcError> {
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
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.select(folder).await
}

#[tauri::command]
pub async fn navigate_workspace(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    intent: NavigationIntent,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.apply(intent).await
}

#[tauri::command]
pub async fn read_archive(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    scope: codex_gui_core::ipc::ArchiveScope,
) -> Result<codex_gui_core::ipc::ArchiveCatalog, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.read_archive(scope).await
}

#[tauri::command]
pub async fn prepare_chat_deletion(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    source: codex_gui_core::ipc::DeleteChatSource,
) -> Result<codex_gui_core::ipc::ConfirmDeleteChat, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.prepare_chat_deletion(source).await
}

#[tauri::command]
pub async fn open_message_search(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    workspace_id: WorkspaceId,
) -> Result<uuid::Uuid, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.open_message_search(workspace_id).await
}

#[tauri::command]
pub async fn read_message_search_page(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: codex_gui_core::ipc::MessageSearchPageRequest,
) -> Result<codex_gui_core::ipc::MessageSearchPage, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.read_message_search_page(request).await
}

#[tauri::command]
pub async fn open_inspector_source(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: codex_gui_core::ipc::InspectorSourceRequest,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let workspace = request.scope.workspace_id;
    let chat = request.scope.chat_id.clone();
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    let url = navigation.inspector_source(request).await?;
    authorize_view(&window)?;
    state.checkout(window.label(), workspace)?;
    state
        .state
        .lock()
        .expect("workspace state lock poisoned")
        .projection
        .read_conversation(workspace, &chat, |_| ())?;
    if *verification == Verification::None {
        open::that_detached(url.as_str()).map_err(|_| IpcError::ProjectUnavailable)?;
    }
    Ok(())
}

#[tauri::command]
pub async fn read_child_history(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: codex_gui_core::ipc::ChildHistoryRequest,
) -> Result<codex_gui_core::ipc::ChildHistoryPage, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.child_history(request).await
}

#[tauri::command]
pub async fn read_inspector_source_detail(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: codex_gui_core::ipc::InspectorSourceRequest,
) -> Result<String, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.inspector_source_detail(request).await
}

#[tauri::command]
pub async fn execute_slash_command(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: codex_gui_core::ipc::ExecuteSlashCommand,
) -> Result<codex_gui_core::ipc::SlashCommandOutcome, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.execute_slash_command(request).await
}

#[tauri::command]
pub async fn open_sent_prompt(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: codex_gui_core::ipc::TranscriptRowRequest,
) -> Result<codex_gui_core::ipc::SentPromptEdit, IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.open_sent_prompt(request).await
}

#[tauri::command]
pub async fn reveal_sidebar_project(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: codex_gui_core::ipc::SidebarProjectRequest,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    let path = navigation.sidebar_project_path(request).await?;
    if *verification == Verification::None {
        tauri_plugin_opener::reveal_item_in_dir(path).map_err(|error| {
            eprintln!("{error}");
            IpcError::ProjectUnavailable
        })?;
    }
    Ok(())
}

#[tauri::command]
pub fn workspace_snapshot(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: WorkspaceRequest,
) -> Result<WorkspaceView, IpcError> {
    authorize_view(&window)?;
    state
        .state
        .lock()
        .expect("workspace state lock poisoned")
        .grants
        .snapshot(window.label(), request)
}

#[tauri::command]
pub async fn search_project_paths(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ProjectPathRequest,
) -> Result<Vec<ProjectPathMatch>, IpcError> {
    authorize_view(&window)?;
    let cache = project.path_index(window.label(), request.workspace_id)?;
    let mut index = cache.lock_owned().await;
    project.checkout(window.label(), request.workspace_id)?;
    let matches = tauri::async_runtime::spawn_blocking(move || index.search(&request.query))
        .await
        .map_err(|_| IpcError::ProjectUnavailable)?;
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    matches.map_err(project_path_error)
}

fn project_path_error(error: codex_gui_core::files::FileError) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}

#[tauri::command]
pub async fn subscribe_workspace(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
) -> Result<WorkspaceSubscription, IpcError> {
    authorize_view(&window)?;
    let mut state = state.state.lock().expect("workspace state lock poisoned");
    state.publish();
    Ok(state.projection.subscribe())
}

#[tauri::command]
pub async fn next_workspace_update(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    request: WorkspaceUpdateRequest,
) -> Result<WorkspaceUpdate, IpcError> {
    authorize_view(&window)?;
    let poll = {
        let mut state = state.state.lock().expect("workspace state lock poisoned");
        state.publish();
        state.projection.poll(request)
    };
    let Some(poll) = poll else {
        return Ok(WorkspaceUpdate::Retired);
    };
    let result = poll.wait(Duration::from_secs(20)).await;
    authorize_view(&window)?;
    Ok(result)
}

#[tauri::command]
pub fn change_workspace_fixture(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    skip_revision: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Streaming {
        return Err(IpcError::UnauthorizedWindow);
    }
    let mut state = state.state.lock().expect("workspace state lock poisoned");
    if state.fixture_directory.is_none() {
        state.fixture_directory = Some(tempfile::tempdir().map_err(|_| IpcError::InvalidCheckout)?);
    }
    let path = state.fixture_directory.as_ref().unwrap().path().to_owned();
    state.select(window.label(), &path)?;
    if skip_revision {
        state.select(window.label(), &path)?;
    }
    Ok(())
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
