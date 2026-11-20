use std::{
    fs::OpenOptions,
    io::Write,
    path::{Path, PathBuf},
};

use codex_gui_core::{
    git::{TrackedFileLink, tracked_file_link},
    ipc::{
        FileAction, FileActionRequest, FileActionsView, FileEditor, FileTabRead, IpcError,
        MarkdownNode,
    },
};
use serde_json::{Value, json};
use tauri::{Manager, State, Url, WebviewWindow};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tokio::sync::oneshot;

use crate::{
    file_tools_ipc::capture_file_scope,
    fixture::{FixtureCheckouts, Verification},
    navigation::FileTabCapture,
    project_ipc::ProjectIpc,
};

mod editors;

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
) -> Result<Option<Vec<MarkdownNode>>, IpcError> {
    let mut source = capture(&window, &project, &target, true).await?;
    let text = String::from_utf8(source.bytes.take().ok_or(IpcError::ProjectUnavailable)?)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    let checkout = source.checkout.clone();
    let markdown = tauri::async_runtime::spawn_blocking(move || {
        crate::transcript_ipc::render_markdown_document(&text, &checkout)
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)?;
    validate(&window, &project, &target, &source).await?;
    Ok(markdown)
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
                tauri::async_runtime::spawn_blocking(move || {
                    write_export(&path, &destination, &bytes)
                })
                .await
                .map_err(|_| IpcError::ProjectUnavailable)??;
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

async fn capture(
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

async fn validate(
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

fn write_export(source: &Path, destination: &Path, bytes: &[u8]) -> Result<(), IpcError> {
    let parent = destination
        .parent()
        .ok_or(IpcError::ProjectUnavailable)?
        .canonicalize()
        .map_err(io_error)?;
    let name = destination
        .file_name()
        .ok_or(IpcError::ProjectUnavailable)?;
    let target = parent.join(name);
    let original = source.canonicalize().map_err(io_error)?;
    if target == source || target.canonicalize().is_ok_and(|path| path == original) {
        return Err(IpcError::StaleSelection);
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
