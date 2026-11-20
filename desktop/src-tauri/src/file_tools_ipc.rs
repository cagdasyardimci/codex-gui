use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{FileError, index::ProjectBrowsePage},
    ipc::{
        DraftAttachmentScope, FileTabEdit, FileTabRead, FileToolsChange, FileToolsRequest,
        FileToolsView, IpcError, ProjectBrowseRequest,
    },
};
use tauri::{State, WebviewWindow, ipc::Response};

use crate::{
    navigation::NavigationHandle,
    project_ipc::{ProjectIpc, authorize_view},
};

#[tauri::command]
pub async fn change_file_tools(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: FileToolsRequest,
) -> Result<FileToolsView, IpcError> {
    let (navigation, _) = capture_file_scope(&window, &project, &request.scope)?;
    let resolved = if let FileToolsChange::Open(open) = &request.change {
        let index = project.path_index(window.label(), request.scope.workspace_id)?;
        let mut index = index.lock_owned().await;
        let path = open.path;
        let resolved = tauri::async_runtime::spawn_blocking(move || index.resolve(path))
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?
            .map_err(index_error)?;
        capture_file_scope(&window, &project, &request.scope)?;
        Some(resolved)
    } else {
        None
    };
    navigation.file_tools(request, resolved).await
}

#[tauri::command]
pub async fn browse_project_files(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ProjectBrowseRequest,
) -> Result<ProjectBrowsePage, IpcError> {
    authorize_view(&window)?;
    let cache = project.path_index(window.label(), request.workspace_id)?;
    let mut index = cache.lock_owned().await;
    let folder = request.folder;
    let offset = request.offset;
    let page = tauri::async_runtime::spawn_blocking(move || index.browse(folder, offset))
        .await
        .map_err(|_| IpcError::ProjectUnavailable)?;
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    page.map_err(index_error)
}

pub(super) fn index_error(error: FileError) -> IpcError {
    match error {
        FileError::InvalidHandle => IpcError::StaleSelection,
        FileError::Checkout(_) => IpcError::RetiredWorkspace,
        _ => IpcError::ProjectUnavailable,
    }
}

#[tauri::command]
pub async fn read_file_tab(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: FileTabRead,
    raster: bool,
) -> Result<Response, IpcError> {
    let (navigation, _) = capture_file_scope(&window, &project, &request.scope)?;
    let scope = request.scope.clone();
    let bytes = navigation.read_file_tab(request, raster).await?;
    capture_file_scope(&window, &project, &scope)?;
    Ok(Response::new(bytes))
}

pub(crate) fn capture_file_scope(
    window: &WebviewWindow,
    project: &ProjectIpc,
    scope: &DraftAttachmentScope,
) -> Result<(NavigationHandle, CheckoutIdentity), IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let checkout = state.grants.checkout(window.label(), scope.workspace_id)?;
    if state.projection.visible_file_tools_scope().as_ref() != Some(scope) {
        return Err(IpcError::StaleSelection);
    }
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?
        .clone();
    Ok((navigation, checkout))
}

#[tauri::command]
pub async fn edit_file_tab(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: FileTabEdit,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?
        .edit_file_tab(request)
        .await
}
