use std::path::{Component, Path, PathBuf};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::local_file_revision,
    ipc::{IpcError, TranscriptImageDependency, TranscriptRowRequest},
};
use percent_encoding::percent_decode_str;
use pulldown_cmark::{Event, Parser, Tag};
use serde_json::Value;
use tauri::{Manager, State, Url, WebviewWindow};
use tauri_plugin_clipboard_manager::ClipboardExt;

use crate::project_ipc::{ProjectIpc, authorize_view};

const MAX_IMAGE_SOURCES: usize = 8;
const MAX_SOURCE_BYTES: usize = 512 * 1024;
const MAX_DEPENDENCY_BYTES: u64 = 32 * 1024 * 1024;

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
        for event in Parser::new(markdown) {
            if let Event::Start(Tag::Image { dest_url, .. }) = event {
                admit(markdown_path(&dest_url));
            }
        }
    }
    paths
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

fn relative_image(checkout: &CheckoutIdentity, path: &Path) -> Option<String> {
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
