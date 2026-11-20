use std::{
    fs::OpenOptions,
    io::Write,
    path::{Path, PathBuf},
};

use codex_gui_core::{
    files::read_local_file,
    git::{TrackedFileLink, tracked_file_link},
    ipc::{
        FileAction, FileActionRequest, FileActionsView, FileEditor, FileMarkdownResource,
        FileTabKind, FileTabRead, IpcError, MarkdownFileView, MarkdownKind,
    },
};
use serde_json::{Value, json};
use tauri::{
    Manager, State, Url, WebviewWindow,
    ipc::{InvokeBody, Request, Response},
};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tokio::sync::oneshot;

use crate::{
    file_tools_ipc::capture_file_scope,
    fixture::{FixtureCheckouts, Verification},
    navigation::FileTabCapture,
    project_ipc::{ProjectIpc, authorize_view},
    transcript_ipc::{MAX_INLINE_BYTES, raster_type},
};

mod editors;
mod markdown;

#[tauri::command]
pub async fn file_tab_actions(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    target: FileTabRead,
) -> Result<FileActionsView, IpcError> {
    let source = capture(&window, &project, &target, false).await?;
    let github = github_url(&source).await.is_some();
    let available = if *verification == Verification::FileTools {
        vec![FileEditor {
            id: "vscode".into(),
            label: "VS Code".into(),
        }]
    } else {
        editors::installed()
            .iter()
            .map(editors::Editor::view)
            .collect()
    };
    validate(&window, &project, &target, &source).await?;
    Ok(FileActionsView {
        editors: available,
        github,
    })
}

#[tauri::command]
pub async fn render_file_markdown(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    target: FileTabRead,
) -> Result<MarkdownFileView, IpcError> {
    let source = capture(&window, &project, &target, true).await?;
    let (source, preview) = tauri::async_runtime::spawn_blocking(move || {
        let preview = render_markdown_capture(&source)?;
        Ok::<_, IpcError>((source, preview))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate(&window, &project, &target, &source).await?;
    Ok(preview)
}

#[tauri::command]
pub async fn file_markdown_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: FileMarkdownResource,
) -> Result<Response, IpcError> {
    let source = capture(&window, &project, &request.target, true).await?;
    let (source, bytes) = tauri::async_runtime::spawn_blocking(move || {
        let preview =
            crate::file_preview_ipc::raster_preview(markdown_image(&source, &request.resource)?)?;
        Ok::<_, IpcError>((source, preview))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate(&window, &project, &request.target, &source).await?;
    Ok(Response::new(bytes))
}

#[tauri::command]
pub async fn export_file_markdown_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: FileMarkdownResource,
) -> Result<(), IpcError> {
    let source = capture(&window, &project, &request.target, true).await?;
    let resource = request.resource;
    let (source, path, bytes) = tauri::async_runtime::spawn_blocking(move || {
        let bytes = markdown_image(&source, &resource)?;
        let path = source.checkout.canonical_path().join(resource);
        Ok::<_, IpcError>((source, path, bytes))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    if let Some(destination) = preview_destination(&window, *verification, &path).await? {
        validate(&window, &project, &request.target, &source).await?;
        persist_export(Some(path), destination, bytes).await?;
    }
    Ok(())
}

fn markdown_image(source: &FileTabCapture, resource: &str) -> Result<Vec<u8>, IpcError> {
    require_markdown_resource(source, MarkdownKind::Image, resource)?;
    let read = read_local_file(&source.checkout, Path::new(resource), 4 * 1024 * 1024)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    Ok(read.bytes)
}

#[tauri::command]
pub async fn export_file_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    target: FileTabRead,
) -> Result<(), IpcError> {
    let source = capture(&window, &project, &target, false).await?;
    if source.kind != FileTabKind::Raster
        && !(source.kind == FileTabKind::Text
            && source
                .relative
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("svg")))
    {
        return Err(IpcError::StaleSelection);
    }
    let (source, path, bytes) = tauri::async_runtime::spawn_blocking(move || {
        let path = source.path()?;
        let bytes = source.preview_bytes(MAX_INLINE_BYTES)?;
        Ok::<_, IpcError>((source, path, bytes))
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    if let Some(destination) = preview_destination(&window, *verification, &path).await? {
        validate(&window, &project, &target, &source).await?;
        persist_export(Some(path), destination, bytes).await?;
    }
    Ok(())
}

#[tauri::command]
pub async fn save_preview_image(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    request: Request<'_>,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let InvokeBody::Raw(bytes) = request.body() else {
        return Err(IpcError::ProjectUnavailable);
    };
    if bytes.len() as u64 > MAX_INLINE_BYTES {
        return Err(IpcError::ProjectUnavailable);
    }
    let kind = request
        .headers()
        .get("x-codex-preview-kind")
        .and_then(|value| value.to_str().ok());
    let name = match (kind, raster_type(bytes)) {
        (Some("diagram"), Some(1)) => "Diagram.png",
        (Some("image"), Some(1)) => "Image.png",
        (Some("image"), Some(2)) => "Image.jpg",
        (Some("image"), Some(3)) => "Image.gif",
        (Some("image"), Some(4)) => "Image.webp",
        _ => return Err(IpcError::ProjectUnavailable),
    };
    let bytes = bytes.clone();
    if let Some(destination) = preview_destination(&window, *verification, Path::new(name)).await? {
        authorize_view(&window)?;
        persist_export(None, destination, bytes).await?;
    }
    Ok(())
}

#[tauri::command]
pub async fn open_file_markdown_link(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: FileMarkdownResource,
) -> Result<(), IpcError> {
    let url = crate::transcript_ipc::markdown_external_url(&request.resource)
        .ok_or(IpcError::StaleSelection)?;
    let source = capture(&window, &project, &request.target, true).await?;
    let source = tauri::async_runtime::spawn_blocking(move || {
        require_markdown_resource(&source, MarkdownKind::Link, &request.resource)?;
        Ok::<_, IpcError>(source)
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    validate(&window, &project, &request.target, &source).await?;
    if *verification == Verification::None {
        open::that_detached(url.as_str()).map_err(io_error)?;
    }
    Ok(())
}

fn render_markdown_capture(source: &FileTabCapture) -> Result<MarkdownFileView, IpcError> {
    let text = std::str::from_utf8(
        source
            .bytes
            .as_deref()
            .ok_or(IpcError::ProjectUnavailable)?,
    )
    .map_err(|_| IpcError::ProjectUnavailable)?;
    let base = source.relative.parent().unwrap_or_else(|| Path::new(""));
    Ok(markdown::render(text, &source.checkout, base))
}

fn require_markdown_resource(
    source: &FileTabCapture,
    kind: MarkdownKind,
    target: &str,
) -> Result<(), IpcError> {
    let preview = render_markdown_capture(source)?;
    if !preview
        .nodes
        .as_ref()
        .is_some_and(|nodes| markdown::declares(nodes, kind, target))
    {
        return Err(IpcError::StaleSelection);
    }
    Ok(())
}

#[tauri::command]
pub async fn perform_file_action(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: FileActionRequest,
) -> Result<(), IpcError> {
    let fixture = *verification == Verification::FileTools;
    let content = matches!(request.action, FileAction::Copy | FileAction::Export);
    let source = capture(&window, &project, &request.target, content).await?;
    let path = source.path()?;
    match request.action {
        FileAction::Copy => {
            let text = std::str::from_utf8(
                source
                    .bytes
                    .as_deref()
                    .ok_or(IpcError::ProjectUnavailable)?,
            )
            .map_err(|_| IpcError::ProjectUnavailable)?;
            if fixture {
                std::fs::write(fixture_data(&window)?.join("copied-file"), text.as_bytes())
                    .map_err(io_error)?;
            } else {
                window
                    .app_handle()
                    .clipboard()
                    .write_text(text)
                    .map_err(|_| IpcError::ProjectUnavailable)?;
            }
        }
        FileAction::Export => {
            let destination = if fixture {
                Some(fixture_data(&window)?.join("exported-file"))
            } else {
                export_destination(&window, &path).await?
            };
            if let Some(destination) = destination {
                validate(&window, &project, &request.target, &source).await?;
                let bytes = source.bytes.ok_or(IpcError::ProjectUnavailable)?;
                persist_export(Some(path), destination, bytes).await?;
            }
        }
        FileAction::Reveal => {
            if fixture {
                record(&window, json!({"action": "reveal", "target": path}))?;
            } else {
                tauri_plugin_opener::reveal_item_in_dir(path)
                    .map_err(|_| IpcError::ProjectUnavailable)?;
            }
        }
        FileAction::OpenDefault => {
            if fixture {
                record(&window, json!({"action": "default", "target": path}))?;
            } else {
                open::that_detached(path).map_err(io_error)?;
            }
        }
        FileAction::OpenEditor(id) => {
            if fixture {
                if id != "vscode" {
                    return Err(IpcError::StaleSelection);
                }
                record(
                    &window,
                    json!({"action": "editor", "editor": id, "target": path}),
                )?;
            } else {
                let editor = editors::installed()
                    .into_iter()
                    .find(|editor| editor.id == id)
                    .ok_or(IpcError::StaleSelection)?;
                validate(&window, &project, &request.target, &source).await?;
                editor.launch(&source.path()?)?;
            }
        }
        FileAction::OpenGitHub => {
            let url = github_url(&source).await.ok_or(IpcError::StaleSelection)?;
            validate(&window, &project, &request.target, &source).await?;
            if fixture {
                record(&window, json!({"action": "github", "target": url.as_str()}))?;
            } else {
                open::that_detached(url.as_str()).map_err(io_error)?;
            }
        }
    }
    Ok(())
}

pub(crate) async fn capture(
    window: &WebviewWindow,
    project: &ProjectIpc,
    target: &FileTabRead,
    bytes: bool,
) -> Result<FileTabCapture, IpcError> {
    let (navigation, _) = capture_file_scope(window, project, &target.scope)?;
    let source = navigation.capture_file_tab(target.clone(), bytes).await?;
    capture_file_scope(window, project, &target.scope)?;
    Ok(source)
}

pub(crate) async fn validate(
    window: &WebviewWindow,
    project: &ProjectIpc,
    target: &FileTabRead,
    source: &FileTabCapture,
) -> Result<(), IpcError> {
    let current = capture(window, project, target, false).await?;
    if !source.same_document(&current) {
        return Err(IpcError::StaleSelection);
    }
    Ok(())
}

async fn github_url(source: &FileTabCapture) -> Option<Url> {
    github_blob_url(
        tracked_file_link(source.checkout.clone(), &source.relative)
            .await
            .ok()?,
    )
}

fn github_blob_url(link: TrackedFileLink) -> Option<Url> {
    let repo = if let Some(path) = link.origin.strip_prefix("git@github.com:") {
        path.to_owned()
    } else {
        let origin = Url::parse(&link.origin).ok()?;
        if origin.host_str() != Some("github.com")
            || !matches!(origin.scheme(), "https" | "ssh")
            || !matches!(origin.username(), "" | "git")
            || origin.password().is_some()
            || origin.port().is_some()
        {
            return None;
        }
        origin.path().trim_matches('/').to_owned()
    };
    let mut segments = repo.strip_suffix(".git").unwrap_or(&repo).split('/');
    let (owner, name) = (segments.next()?, segments.next()?);
    if segments.next().is_some()
        || [owner, name].iter().any(|name| {
            name.is_empty()
                || matches!(*name, "." | "..")
                || !name
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"-_.".contains(&byte))
        })
    {
        return None;
    }
    let mut url = Url::parse("https://github.com/").ok()?;
    {
        let mut path = url.path_segments_mut().ok()?;
        path.clear()
            .extend([owner, name, "blob", link.commit.as_str()]);
        path.extend(link.relative.split('/'));
    }
    Some(url)
}

async fn export_destination(
    window: &WebviewWindow,
    path: &Path,
) -> Result<Option<PathBuf>, IpcError> {
    let name = path
        .file_name()
        .ok_or(IpcError::StaleSelection)?
        .to_string_lossy();
    let (send, receive) = oneshot::channel();
    window
        .app_handle()
        .dialog()
        .file()
        .set_file_name(name)
        .save_file(move |path| {
            let _ = send.send(path);
        });
    receive
        .await
        .map_err(|_| IpcError::ProjectUnavailable)?
        .map(|path| path.into_path().map_err(|_| IpcError::ProjectUnavailable))
        .transpose()
}

async fn preview_destination(
    window: &WebviewWindow,
    verification: Verification,
    path: &Path,
) -> Result<Option<PathBuf>, IpcError> {
    if matches!(
        verification,
        Verification::FileTools | Verification::History
    ) {
        let name = path.file_name().ok_or(IpcError::StaleSelection)?;
        return Ok(Some(
            fixture_data(window)?.join(format!("preview-{}", name.to_string_lossy())),
        ));
    }
    export_destination(window, path).await
}

async fn persist_export(
    source: Option<PathBuf>,
    destination: PathBuf,
    bytes: Vec<u8>,
) -> Result<(), IpcError> {
    tauri::async_runtime::spawn_blocking(move || {
        write_export(source.as_deref(), &destination, &bytes)
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)?
}

fn write_export(source: Option<&Path>, destination: &Path, bytes: &[u8]) -> Result<(), IpcError> {
    let parent = destination
        .parent()
        .ok_or(IpcError::ProjectUnavailable)?
        .canonicalize()
        .map_err(io_error)?;
    let name = destination
        .file_name()
        .ok_or(IpcError::ProjectUnavailable)?;
    let target = parent.join(name);
    if let Some(source) = source {
        let original = source.canonicalize().map_err(io_error)?;
        if target == source || target.canonicalize().is_ok_and(|path| path == original) {
            return Err(IpcError::StaleSelection);
        }
    }
    let mut staging = tempfile::NamedTempFile::new_in(parent).map_err(io_error)?;
    staging.write_all(bytes).map_err(io_error)?;
    staging.as_file().sync_all().map_err(io_error)?;
    staging
        .persist(target)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    Ok(())
}

fn fixture_data(window: &WebviewWindow) -> Result<PathBuf, IpcError> {
    window
        .state::<FixtureCheckouts>()
        .data
        .clone()
        .ok_or(IpcError::UnauthorizedWindow)
}

fn record(window: &WebviewWindow, action: Value) -> Result<(), IpcError> {
    let data = fixture_data(window)?;
    let mut log = OpenOptions::new()
        .append(true)
        .create(true)
        .open(data.join("file-actions.jsonl"))
        .map_err(io_error)?;
    writeln!(log, "{action}").map_err(io_error)
}

fn io_error(error: std::io::Error) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
