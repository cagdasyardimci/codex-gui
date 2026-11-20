use std::path::{Path, PathBuf};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{CheckoutFiles, read_local_file},
    ipc::{DraftAttachmentRequest, DraftAttachmentScope, IpcError, ReuseAttachmentRequest},
    storage::{
        attachments::{
            AttachmentStore,
            composer::{ComposerAttachment, ComposerAttachmentKind, MAX_COMPOSER_ATTACHMENTS},
        },
        drafts::DraftId,
    },
};
use percent_encoding::percent_decode_str;
use tauri::{
    State, WebviewWindow,
    ipc::{InvokeBody, Request, Response},
};
use tauri_plugin_dialog::DialogExt;
use uuid::Uuid;

use crate::{
    fixture::Verification,
    navigation::{ComposerAttachmentMutation, NavigationHandle},
    project_ipc::{ProjectIpc, authorize_view},
    transcript_ipc::{
        MAX_INLINE_BYTES, inline_raster_payload, raster_type, read_attachment_image,
        scoped_attachment,
    },
};

#[tauri::command]
pub async fn pick_composer_attachments(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    scope: DraftAttachmentScope,
) -> Result<(), IpcError> {
    let (navigation, checkout) = capture(&window, &project, &scope)?;
    let _picker = project.reserve_picker()?;
    if *verification == Verification::Attachments {
        let path = checkout.canonical_path().join("picked.png");
        tokio::time::sleep(std::time::Duration::from_millis(350)).await;
        return add_paths(navigation, checkout, scope, vec![path]).await;
    }
    let (reply, result) = tokio::sync::oneshot::channel();
    window
        .dialog()
        .file()
        .set_parent(&window)
        .set_title("Attach Files")
        .pick_files(move |files| {
            let _ = reply.send(files);
        });
    let Some(files) = result.await.map_err(|_| IpcError::ProjectUnavailable)? else {
        return Ok(());
    };
    let paths = files
        .into_iter()
        .map(|file| file.into_path().map_err(|_| IpcError::ProjectUnavailable))
        .collect::<Result<Vec<_>, _>>()?;
    add_paths(navigation, checkout, scope, paths).await
}

#[tauri::command]
pub async fn drop_composer_attachment_fixture(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    scope: DraftAttachmentScope,
) -> Result<(), IpcError> {
    if *verification != Verification::Attachments {
        return Err(IpcError::UnauthorizedWindow);
    }
    let (navigation, checkout) = capture(&window, &project, &scope)?;
    let path = checkout.canonical_path().join("notes.txt");
    add_paths(navigation, checkout, scope, vec![path]).await
}

#[tauri::command]
pub async fn paste_composer_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: Request<'_>,
) -> Result<(), IpcError> {
    let header = request
        .headers()
        .get("x-codex-attachment-scope")
        .and_then(|header| header.to_str().ok())
        .filter(|header| header.len() <= 4096)
        .ok_or(IpcError::StaleSelection)?;
    let decoded = percent_decode_str(header)
        .decode_utf8()
        .map_err(|_| IpcError::StaleSelection)?;
    let scope = serde_json::from_str(&decoded).map_err(|_| IpcError::StaleSelection)?;
    let (navigation, _) = capture(&window, &project, &scope)?;
    let InvokeBody::Raw(bytes) = request.body() else {
        return Err(IpcError::ProjectUnavailable);
    };
    if bytes.len() as u64 > MAX_INLINE_BYTES || raster_type(bytes).is_none() {
        return Err(IpcError::ProjectUnavailable);
    }
    let store = navigation.attachment_store().clone();
    let bytes = bytes.clone();
    let image = tauri::async_runtime::spawn_blocking(move || store.stage(bytes.as_slice()))
        .await
        .map_err(|_| IpcError::ProjectUnavailable)?
        .map_err(|_| IpcError::ProjectUnavailable)?;
    navigation
        .mutate_attachments(ComposerAttachmentMutation::Append(
            scope,
            vec![ComposerAttachment {
                id: Uuid::new_v4().to_string(),
                title: "Pasted image".into(),
                kind: ComposerAttachmentKind::Image(image),
            }],
        ))
        .await
}

#[tauri::command]
pub async fn remove_composer_attachment(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: DraftAttachmentRequest,
) -> Result<(), IpcError> {
    let (navigation, _) = capture(&window, &project, &request.scope)?;
    navigation
        .mutate_attachments(ComposerAttachmentMutation::Remove(request))
        .await
}

#[tauri::command]
pub async fn reuse_composer_attachment(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ReuseAttachmentRequest,
) -> Result<(), IpcError> {
    let (navigation, checkout) = capture(&window, &project, &request.scope)?;
    if request.scope.workspace_id != request.media.row.workspace_id {
        return Err(IpcError::StaleSelection);
    }
    let (_, media) = scoped_attachment(&window, &project, &request.media)?;
    let thread = request.media.row.chat_id.clone();
    let store = navigation.attachment_store().clone();
    let entry = tauri::async_runtime::spawn_blocking(move || {
        let kind = if media.image {
            let bytes = read_attachment_image(&checkout, &store, &thread, &media)?;
            if raster_type(&bytes).is_none() {
                return Err(IpcError::ProjectUnavailable);
            }
            ComposerAttachmentKind::Image(
                store
                    .stage(bytes.as_slice())
                    .map_err(|_| IpcError::ProjectUnavailable)?,
            )
        } else {
            CheckoutFiles::new(checkout)
                .issue(Path::new(&media.path))
                .map_err(|_| IpcError::ProjectUnavailable)?;
            ComposerAttachmentKind::File(media.path)
        };
        Ok::<_, IpcError>(ComposerAttachment {
            id: Uuid::new_v4().to_string(),
            title: media.label,
            kind,
        })
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    navigation
        .mutate_attachments(ComposerAttachmentMutation::Append(
            request.scope,
            vec![entry],
        ))
        .await
}

#[tauri::command]
pub async fn load_composer_image(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: DraftAttachmentRequest,
) -> Result<Response, IpcError> {
    let (navigation, _) = capture(&window, &project, &request.scope)?;
    let draft =
        DraftId(Uuid::parse_str(&request.scope.draft_id).map_err(|_| IpcError::StaleSelection)?);
    let store = navigation.attachment_store().clone();
    let id = request.attachment_id.clone();
    let bytes = tauri::async_runtime::spawn_blocking(move || {
        let lease = store
            .lease_composer_image(draft, &id)
            .map_err(|_| IpcError::StaleSelection)?;
        lease
            .read_preview(MAX_INLINE_BYTES)
            .map_err(|_| IpcError::ProjectUnavailable)
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    capture(&window, &project, &request.scope)?;
    navigation
        .attachment_store()
        .lease_composer_image(draft, &request.attachment_id)
        .map_err(|_| IpcError::StaleSelection)?;
    Ok(Response::new(inline_raster_payload(bytes)?))
}

pub(crate) fn dropped_paths(window: WebviewWindow, project: &ProjectIpc, paths: Vec<PathBuf>) {
    let Some(scope) = project
        .state
        .lock()
        .expect("workspace state lock poisoned")
        .projection
        .visible_attachment_scope()
    else {
        return;
    };
    let Ok((navigation, checkout)) = capture(&window, project, &scope) else {
        return;
    };
    tauri::async_runtime::spawn(async move {
        let _ = add_paths(navigation, checkout, scope, paths).await;
    });
}

fn capture(
    window: &WebviewWindow,
    project: &ProjectIpc,
    scope: &DraftAttachmentScope,
) -> Result<(NavigationHandle, CheckoutIdentity), IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let checkout = state.grants.checkout(window.label(), scope.workspace_id)?;
    if state.projection.visible_attachment_scope().as_ref() != Some(scope) {
        return Err(IpcError::StaleSelection);
    }
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?
        .clone();
    Ok((navigation, checkout))
}

async fn add_paths(
    navigation: NavigationHandle,
    checkout: CheckoutIdentity,
    scope: DraftAttachmentScope,
    paths: Vec<PathBuf>,
) -> Result<(), IpcError> {
    if paths.is_empty() {
        return Ok(());
    }
    if paths.len() > MAX_COMPOSER_ATTACHMENTS {
        return Err(IpcError::ProjectUnavailable);
    }
    let store = navigation.attachment_store().clone();
    let added = tauri::async_runtime::spawn_blocking(move || {
        paths
            .into_iter()
            .map(|path| capture_path(&checkout, &store, &path))
            .collect::<Result<Vec<_>, _>>()
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    navigation
        .mutate_attachments(ComposerAttachmentMutation::Append(scope, added))
        .await
}

fn capture_path(
    checkout: &CheckoutIdentity,
    store: &AttachmentStore,
    path: &Path,
) -> Result<ComposerAttachment, IpcError> {
    let name = path.file_name().ok_or(IpcError::ProjectUnavailable)?;
    let parent = path.parent().ok_or(IpcError::ProjectUnavailable)?;
    let parent = CheckoutIdentity::capture(parent).map_err(|_| IpcError::ProjectUnavailable)?;
    let kind = match read_local_file(&parent, Path::new(name), MAX_INLINE_BYTES) {
        Ok(read) if raster_type(&read.bytes).is_some() => ComposerAttachmentKind::Image(
            store
                .stage(read.bytes.as_slice())
                .map_err(|_| IpcError::ProjectUnavailable)?,
        ),
        _ => {
            let canonical = parent.canonical_path().join(name);
            let relative = canonical
                .strip_prefix(checkout.canonical_path())
                .map_err(|_| IpcError::StaleSelection)?;
            CheckoutFiles::new(checkout.clone())
                .issue(relative)
                .map_err(|_| IpcError::ProjectUnavailable)?;
            ComposerAttachmentKind::File(
                relative
                    .to_str()
                    .ok_or(IpcError::ProjectUnavailable)?
                    .to_owned(),
            )
        }
    };
    Ok(ComposerAttachment {
        id: Uuid::new_v4().to_string(),
        title: name.to_string_lossy().into_owned(),
        kind,
    })
}
