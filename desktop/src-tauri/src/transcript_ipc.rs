use std::path::{Component, Path, PathBuf};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{local_file_revision, read_local_file},
    ipc::{
        IpcError, MarkdownNode, MarkdownTargetRequest, TranscriptAttachment,
        TranscriptAttachmentLocation, TranscriptImageDependency, TranscriptMediaRequest,
        TranscriptRowRequest,
    },
    storage::attachments::AttachmentStore,
};
use percent_encoding::percent_decode_str;
use pulldown_cmark::{Event, Tag};
use serde_json::Value;
use tauri::{Manager, State, Url, WebviewWindow, ipc::Response};
use tauri_plugin_clipboard_manager::ClipboardExt;

use crate::{
    fixture::Verification,
    project_ipc::{ProjectIpc, authorize_view},
};

mod markdown;

const MAX_IMAGE_SOURCES: usize = 8;
const MAX_SOURCE_BYTES: usize = 512 * 1024;
const MAX_DEPENDENCY_BYTES: u64 = 32 * 1024 * 1024;
pub(crate) const MAX_INLINE_BYTES: u64 = 20 * 1024 * 1024;

#[tauri::command]
pub async fn render_transcript_markdown(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: TranscriptRowRequest,
) -> Result<Option<Vec<MarkdownNode>>, IpcError> {
    let (checkout, source) = authorized_source(&window, &project, &request)?;
    let result =
        tauri::async_runtime::spawn_blocking(move || markdown::document(&source, &checkout))
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?;
    authorized_source(&window, &project, &request)?;
    Ok(result)
}

#[tauri::command]
pub async fn load_transcript_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: MarkdownTargetRequest,
) -> Result<Response, IpcError> {
    let checkout = authorized_image(&window, &project, &request)?;
    let path = request.target.clone();
    let bytes =
        tauri::async_runtime::spawn_blocking(move || checked_inline_image(&checkout, &path))
            .await
            .map_err(|_| IpcError::ProjectUnavailable)??;
    authorized_image(&window, &project, &request)?;
    Ok(Response::new(bytes))
}

#[tauri::command]
pub async fn load_transcript_attachment(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: TranscriptMediaRequest,
) -> Result<Response, IpcError> {
    let (checkout, media) = scoped_attachment(&window, &project, &request)?;
    let thread = request.row.chat_id.clone();
    let store = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?
        .attachment_store()
        .clone();
    let bytes = tauri::async_runtime::spawn_blocking(move || {
        read_attachment_image(&checkout, &store, &thread, &media)
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    scoped_attachment(&window, &project, &request)?;
    Ok(Response::new(inline_raster_payload(bytes)?))
}

pub(crate) fn scoped_attachment(
    window: &WebviewWindow,
    project: &ProjectIpc,
    request: &TranscriptMediaRequest,
) -> Result<(CheckoutIdentity, TranscriptAttachmentLocation), IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let checkout = state
        .grants
        .checkout(window.label(), request.row.workspace_id)?;
    let media = state.projection.transcript_attachment(request)?;
    Ok((checkout, media))
}

pub(crate) fn read_attachment_image(
    checkout: &CheckoutIdentity,
    store: &AttachmentStore,
    thread: &str,
    media: &TranscriptAttachmentLocation,
) -> Result<Vec<u8>, IpcError> {
    if !media.image {
        return Err(IpcError::StaleSelection);
    }
    let path = Path::new(&media.path);
    if path.is_absolute() {
        let lease = store
            .lease_sent_image(checkout, thread, &media.turn_id, path)
            .map_err(|_| IpcError::StaleSelection)?;
        lease
            .read_preview(MAX_INLINE_BYTES)
            .map_err(|_| IpcError::ProjectUnavailable)
    } else {
        read_local_file(checkout, path, MAX_INLINE_BYTES)
            .map(|read| read.bytes)
            .map_err(|_| IpcError::ProjectUnavailable)
    }
}

#[tauri::command]
pub fn open_transcript_link(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    request: MarkdownTargetRequest,
) -> Result<(), IpcError> {
    let (checkout, source) = authorized_source(&window, &project, &request.row)?;
    let url = markdown::external_url(&request.target).ok_or(IpcError::StaleSelection)?;
    let nodes = markdown::document(&source, &checkout).ok_or(IpcError::StaleSelection)?;
    if !markdown::contains_link(&nodes, url.as_str()) {
        return Err(IpcError::StaleSelection);
    }
    authorized_source(&window, &project, &request.row)?;
    if *verification.inner() == Verification::None {
        open::that_detached(url.as_str()).map_err(|_| IpcError::ProjectUnavailable)?;
    }
    Ok(())
}

fn authorized_source(
    window: &WebviewWindow,
    project: &ProjectIpc,
    request: &TranscriptRowRequest,
) -> Result<(CheckoutIdentity, String), IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let checkout = state
        .grants
        .checkout(window.label(), request.workspace_id)?;
    Ok((checkout, state.projection.transcript_markdown(request)?))
}

fn authorized_image(
    window: &WebviewWindow,
    project: &ProjectIpc,
    request: &MarkdownTargetRequest,
) -> Result<CheckoutIdentity, IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let checkout = state
        .grants
        .checkout(window.label(), request.row.workspace_id)?;
    let declared = state.projection.transcript_images(&request.row)?;
    if !declared.contains(&request.target) {
        return Err(IpcError::StaleSelection);
    }
    Ok(checkout)
}

fn checked_inline_image(checkout: &CheckoutIdentity, path: &str) -> Result<Vec<u8>, IpcError> {
    let read = read_local_file(checkout, Path::new(path), MAX_INLINE_BYTES)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    inline_raster_payload(read.bytes)
}

pub(crate) fn raster_type(bytes: &[u8]) -> Option<u8> {
    Some(if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        1
    } else if bytes.starts_with(b"\xff\xd8\xff") {
        2
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        3
    } else if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP") {
        4
    } else {
        return None;
    })
}

pub(crate) fn inline_raster_payload(bytes: Vec<u8>) -> Result<Vec<u8>, IpcError> {
    let format = raster_type(&bytes).ok_or(IpcError::ProjectUnavailable)?;
    let mut payload = Vec::with_capacity(1 + bytes.len());
    payload.push(format);
    payload.extend(bytes);
    Ok(payload)
}

#[tauri::command]
pub fn copy_transcript_row(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: TranscriptRowRequest,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let source = {
        let state = project.state.lock().expect("workspace state lock poisoned");
        state
            .grants
            .checkout(window.label(), request.workspace_id)?;
        state.projection.copy_transcript_source(&request)?
    };
    window
        .app_handle()
        .clipboard()
        .write_text(source)
        .map_err(|error| {
            eprintln!("{error}");
            IpcError::ProjectUnavailable
        })
}

#[tauri::command]
pub async fn check_transcript_images(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: TranscriptRowRequest,
) -> Result<Vec<TranscriptImageDependency>, IpcError> {
    authorize_view(&window)?;
    let (checkout, paths) = {
        let state = project.state.lock().expect("workspace state lock poisoned");
        (
            state
                .grants
                .checkout(window.label(), request.workspace_id)?,
            state.projection.transcript_images(&request)?,
        )
    };
    let dependencies =
        tauri::async_runtime::spawn_blocking(move || checked_dependencies(&checkout, paths))
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?;
    authorize_view(&window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    state
        .grants
        .checkout(window.label(), request.workspace_id)?;
    state.projection.transcript_images(&request)?;
    Ok(dependencies)
}

pub(crate) fn local_images(
    checkout: &CheckoutIdentity,
    markdown: &str,
    item: &Value,
) -> Vec<String> {
    let mut paths = Vec::new();
    let mut admit = |candidate: Option<PathBuf>| {
        if paths.len() >= MAX_IMAGE_SOURCES {
            return;
        }
        if let Some(path) = candidate.and_then(|path| relative_image(checkout, &path))
            && !paths.contains(&path)
        {
            paths.push(path);
        }
    };
    if let Some(content) = item["content"].as_array() {
        for image in content.iter().filter(|value| value["type"] == "localImage") {
            admit(image["path"].as_str().map(PathBuf::from));
        }
    }
    if markdown.len() <= MAX_SOURCE_BYTES && markdown.contains("![") {
        for event in markdown::events(markdown) {
            if let Event::Start(Tag::Image { dest_url, .. }) = event {
                admit(markdown_path(&dest_url));
            }
        }
    }
    paths
}

pub(crate) fn local_attachments(
    checkout: &CheckoutIdentity,
    item: &Value,
) -> Vec<TranscriptAttachment> {
    item["content"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|value| {
            let image = match value["type"].as_str()? {
                "localImage" => true,
                "mention" => false,
                _ => return None,
            };
            let path = Path::new(value["path"].as_str()?);
            let name = path.file_name()?.to_str()?;
            if let Some(relative) = relative_image(checkout, path) {
                return Some((relative, name.to_owned(), image));
            }
            if image
                && path.is_absolute()
                && name.len() == 64
                && name.bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Some((path.to_str()?.to_owned(), "Image".into(), true));
            }
            None
        })
        .take(MAX_IMAGE_SOURCES)
        .enumerate()
        .map(
            |(index, (relative_path, label, image))| TranscriptAttachment {
                id: index as u32,
                label,
                image,
                relative_path,
            },
        )
        .collect()
}

fn markdown_path(destination: &str) -> Option<PathBuf> {
    if let Ok(url) = Url::parse(destination)
        && url.scheme().len() > 1
    {
        return url.to_file_path().ok();
    }
    let path = destination.split(['#', '?']).next()?;
    Some(PathBuf::from(
        percent_decode_str(path).decode_utf8().ok()?.into_owned(),
    ))
}

pub(crate) fn relative_image(checkout: &CheckoutIdentity, path: &Path) -> Option<String> {
    let root = checkout.canonical_path();
    #[cfg(windows)]
    let (root, path) = (dunce::simplified(root), dunce::simplified(path));
    let relative = if path.is_absolute() {
        path.strip_prefix(root).ok()?
    } else {
        path
    };
    let mut components = Vec::new();
    for component in relative.components() {
        match component {
            Component::Normal(name) => {
                let name = name.to_str()?;
                if name.contains('\0') {
                    return None;
                }
                components.push(name);
            }
            Component::CurDir => {}
            _ => return None,
        }
    }
    (!components.is_empty()).then(|| components.join("/"))
}

fn checked_dependencies(
    checkout: &CheckoutIdentity,
    paths: Vec<String>,
) -> Vec<TranscriptImageDependency> {
    let mut left = MAX_DEPENDENCY_BYTES;
    paths
        .into_iter()
        .map(|path| {
            let revision = local_file_revision(checkout, Path::new(&path), left).ok();
            if let Some(revision) = &revision {
                left -= revision.byte_count as u64;
            }
            TranscriptImageDependency { path, revision }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::fs;

    #[test]
    fn only_admits_checkout_images_and_detects_changed_bytes_at_the_same_path() {
        let temp = tempfile::tempdir().unwrap();
        let checkout = CheckoutIdentity::capture(temp.path()).unwrap();
        let root = checkout.canonical_path();
        let file = root.join("first image.png");
        fs::write(&file, b"first bytes").unwrap();
        let wire = json!({"content": [{"type":"localImage", "path": file}, {"type":"localImage", "path":"../outside.png"}]});
        let markdown = "![first][image]\n![fresh](./second.png)\n![network](https://example.test/remote.png)\n`![literal](third.png)`\n\n[image]: first%20image.png";
        let declared = local_images(&checkout, markdown, &wire);
        assert_eq!(declared, ["first image.png", "second.png"]);
        let before = checked_dependencies(&checkout, declared.clone());
        assert!(before[0].revision.is_some());
        assert!(before[1].revision.is_none());
        fs::write(&file, b"after bytes").unwrap();
        let after = checked_dependencies(&checkout, declared.clone());
        assert_ne!(before[0].revision, after[0].revision);
        fs::remove_file(file).unwrap();
        assert!(
            checked_dependencies(&checkout, declared)
                .iter()
                .all(|file| file.revision.is_none())
        );
    }
}
