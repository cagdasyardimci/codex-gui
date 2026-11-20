use std::path::PathBuf;

use codex_gui_core::ipc::{
    DiffAction, DiffActionRequest, DiffMediaRequest, DiffRichKind, MarkdownNode,
};
use tauri::{Manager, ipc::Response};
use tauri_plugin_clipboard_manager::ClipboardExt;

use super::*;
use crate::{
    file_actions_ipc::{export_destination, fixture_data, persist_export},
    file_preview_ipc::raster_preview,
    transcript_ipc::render_markdown_document,
};

#[tauri::command]
pub async fn checkout_diff_media(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: DiffMediaRequest,
) -> Result<Response, IpcError> {
    let (scope, selected) = state.get_selected(&request.target)?;
    validate_selection(
        &window,
        &project,
        &state,
        &request.target,
        &scope,
        &selected,
    )
    .await?;
    let indexed = selected.clone();
    let bytes = tauri::async_runtime::spawn_blocking(move || {
        let content = indexed
            .capture
            .contents(request.side)
            .ok_or(IpcError::StaleSelection)?;
        match content.rich() {
            Some(DiffRichKind::Raster) => raster_preview(content.bytes.clone()),
            Some(DiffRichKind::Pdf) => Ok(content.bytes.clone()),
            _ => Err(IpcError::StaleSelection),
        }
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate_selection(
        &window,
        &project,
        &state,
        &request.target,
        &scope,
        &selected,
    )
    .await?;
    Ok(Response::new(bytes))
}

#[tauri::command]
pub async fn checkout_diff_markdown(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: DiffMediaRequest,
) -> Result<Option<Vec<MarkdownNode>>, IpcError> {
    let (scope, selected) = state.get_selected(&request.target)?;
    validate_selection(
        &window,
        &project,
        &state,
        &request.target,
        &scope,
        &selected,
    )
    .await?;
    let indexed = selected.clone();
    let checkout = scope.checkout.clone();
    let rendered = tauri::async_runtime::spawn_blocking(move || {
        let content = indexed
            .capture
            .contents(request.side)
            .ok_or(IpcError::StaleSelection)?;
        if !matches!(content.rich(), Some(DiffRichKind::Markdown)) {
            return Err(IpcError::StaleSelection);
        }
        let text = std::str::from_utf8(&content.bytes).map_err(|_| IpcError::ProjectUnavailable)?;
        Ok(render_markdown_document(text, &checkout))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate_selection(
        &window,
        &project,
        &state,
        &request.target,
        &scope,
        &selected,
    )
    .await?;
    Ok(rendered)
}

#[tauri::command]
pub async fn checkout_diff_action(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    verification: State<'_, Verification>,
    request: DiffActionRequest,
) -> Result<(), IpcError> {
    let (scope, selected) = state.get_selected(&request.target)?;
    validate_selection(
        &window,
        &project,
        &state,
        &request.target,
        &scope,
        &selected,
    )
    .await?;
    let fixture = *verification == Verification::Diff;
    match request.action {
        DiffAction::CopyPatch => {
            let text = String::from_utf8_lossy(&selected.capture.patch);
            if fixture {
                std::fs::write(fixture_data(&window)?.join("diff-copied"), text.as_bytes())
                    .map_err(io_error)?;
            } else {
                window
                    .app_handle()
                    .clipboard()
                    .write_text(text)
                    .map_err(|_| IpcError::ProjectUnavailable)?;
            }
        }
        DiffAction::ExportPatch | DiffAction::ExportFile(_) => {
            let (name, bytes, source) = match request.action {
                DiffAction::ExportPatch if selected.capture.patch_exportable => (
                    PathBuf::from(format!(
                        "{}.patch",
                        captured_name(&selected.path)?.display()
                    )),
                    selected.capture.patch.clone(),
                    None,
                ),
                DiffAction::ExportFile(side) => {
                    let content = selected
                        .capture
                        .contents(side)
                        .ok_or(IpcError::StaleSelection)?;
                    let source = scope.checkout.canonical_path().join(&content.path);
                    (
                        captured_name(&content.path)?.to_path_buf(),
                        content.bytes.clone(),
                        Some(source),
                    )
                }
                _ => return Err(IpcError::StaleSelection),
            };
            let destination = if fixture {
                let suffix = if matches!(request.action, DiffAction::ExportPatch) {
                    "patch"
                } else {
                    "file"
                };
                Some(fixture_data(&window)?.join(format!("diff-exported-{suffix}")))
            } else {
                export_destination(&window, &name).await?
            };
            if let Some(destination) = destination {
                validate_selection(
                    &window,
                    &project,
                    &state,
                    &request.target,
                    &scope,
                    &selected,
                )
                .await?;
                persist_export(source, destination, bytes).await?;
            }
        }
        DiffAction::OpenEditor { side, editor } => {
            let content = selected
                .capture
                .contents(side)
                .ok_or(IpcError::StaleSelection)?;
            let launcher = if fixture {
                if editor != "vscode" {
                    return Err(IpcError::StaleSelection);
                }
                None
            } else {
                Some(
                    editors::installed()
                        .into_iter()
                        .find(|installed| installed.id == editor)
                        .ok_or(IpcError::StaleSelection)?,
                )
            };
            let path = if fixture {
                fixture_data(&window)?.join("diff-editor-file")
            } else {
                state.editor_path(captured_name(&content.path)?)?
            };
            persist_export(None, path.clone(), content.bytes.clone()).await?;
            validate_selection(
                &window,
                &project,
                &state,
                &request.target,
                &scope,
                &selected,
            )
            .await?;
            if let Some(launcher) = launcher {
                launcher.launch(&path)?;
            }
        }
    }
    Ok(())
}

impl DiffIpc {
    fn editor_path(&self, name: &Path) -> Result<PathBuf, IpcError> {
        let mut directory = self
            .editor_directory
            .lock()
            .expect("editor directory lock poisoned");
        if directory.is_none() {
            *directory = Some(
                tempfile::Builder::new()
                    .prefix("codex-compared-files-")
                    .tempdir()
                    .map_err(io_error)?,
            );
        }
        let target = directory
            .as_ref()
            .expect("editor directory was created")
            .path()
            .join(Uuid::new_v4().to_string());
        std::fs::create_dir(&target).map_err(io_error)?;
        Ok(target.join(name))
    }
}

async fn validate_selection(
    window: &WebviewWindow,
    project: &ProjectIpc,
    state: &DiffIpc,
    target: &DiffPatchRequest,
    scope: &Arc<Scope>,
    selection: &Arc<Selection>,
) -> Result<(), IpcError> {
    validate_scope(window, project, scope).await?;
    let (current, selected) = state.get_selected(target)?;
    if !Arc::ptr_eq(scope, &current) || !Arc::ptr_eq(selection, &selected) {
        return Err(IpcError::StaleSelection);
    }
    Ok(())
}

fn io_error(error: std::io::Error) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
