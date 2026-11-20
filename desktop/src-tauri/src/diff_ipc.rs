use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use codex_gui_core::{
    git::{CheckoutDiff, GitChange, GitError},
    ipc::{DiffFileView, DiffPatchRequest, DiffPatchView, IpcError, WorkspaceId, WorkspaceRequest},
};
use tauri::{State, WebviewWindow};
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

#[derive(Default)]
pub struct DiffIpc {
    state: Mutex<QueryState>,
}

#[derive(Default)]
struct QueryState {
    generation: Uuid,
    published: Option<Scope>,
}

struct Scope {
    workspace: WorkspaceId,
    checkout: Arc<CheckoutDiff>,
    files: HashMap<String, GitChange>,
}

#[tauri::command]
pub async fn checkout_changes(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: WorkspaceRequest,
) -> Result<Vec<DiffFileView>, IpcError> {
    authorize_view(&window)?;
    let owner = project.checkout(window.label(), request.workspace_id)?;
    let generation = Uuid::new_v4();
    {
        let mut state = state.state.lock().expect("changes query lock poisoned");
        state.generation = generation;
        state.published = None;
    }
    let checkout = Arc::new(CheckoutDiff::open(owner).await.map_err(report)?);
    let changes = checkout.changes().await.map_err(report)?;
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    let mut state = state.state.lock().expect("changes query lock poisoned");
    if state.generation != generation {
        return Err(IpcError::StaleSelection);
    }
    let mut files = HashMap::with_capacity(changes.len());
    let mut view = Vec::with_capacity(changes.len());
    for file in changes {
        let file_id = Uuid::new_v4().to_string();
        view.push(DiffFileView {
            file_id: file_id.clone(),
            path: file.display_path(),
        });
        files.insert(file_id, file);
    }
    state.published = Some(Scope {
        workspace: request.workspace_id,
        checkout,
        files,
    });
    Ok(view)
}

#[tauri::command]
pub async fn checkout_patch(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: DiffPatchRequest,
) -> Result<DiffPatchView, IpcError> {
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    let (generation, checkout, file) = {
        let state = state.state.lock().expect("changes query lock poisoned");
        let scope = state
            .published
            .as_ref()
            .filter(|scope| scope.workspace == request.workspace_id)
            .ok_or(IpcError::StaleSelection)?;
        let file = scope
            .files
            .get(&request.file_id)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        (state.generation, scope.checkout.clone(), file)
    };
    let text = checkout.patch(&file).await.map_err(report)?;
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    if state
        .state
        .lock()
        .expect("changes query lock poisoned")
        .generation
        != generation
    {
        return Err(IpcError::StaleSelection);
    }
    Ok(DiffPatchView {
        file_id: request.file_id,
        text,
    })
}

fn report(error: GitError) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
