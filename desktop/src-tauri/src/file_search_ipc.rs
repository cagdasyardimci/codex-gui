use std::{
    collections::HashMap,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{
        FileError,
        search::{ContentMatch, ContentSearchError, FileContentSearch, OpenedSearchFile},
    },
    ipc::{
        DraftAttachmentScope, FileSearchPage, FileSearchResult, IpcError, OpenFileSearchHit,
        OpenedFileSearchHit, ReadFileSearch, StartFileSearch,
    },
};
use tauri::{State, WebviewWindow};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::{
    file_tools_ipc::{capture_file_scope, index_error},
    project_ipc::{ProjectIpc, authorize_view},
};

pub(crate) struct FileSearchSession {
    id: Uuid,
    scope: DraftAttachmentScope,
    checkout: CheckoutIdentity,
    query: String,
    mask: String,
    canceled: AtomicBool,
    scan: Arc<Mutex<SearchProgress>>,
}

#[derive(Default)]
struct SearchProgress {
    reader: Option<FileContentSearch>,
    cursor: Option<Uuid>,
    finished: bool,
    matches: HashMap<Uuid, ContentMatch>,
}

pub(crate) struct PreparedFileHit {
    session: Arc<FileSearchSession>,
    pub file: OpenedSearchFile,
}

impl PreparedFileHit {
    pub fn scope(&self) -> &DraftAttachmentScope {
        &self.session.scope
    }

    pub fn still_current(&self) -> bool {
        !self.session.canceled.load(Ordering::Acquire)
    }
}

impl FileSearchSession {
    pub fn cancel(&self) {
        self.canceled.store(true, Ordering::Release);
    }
}

#[tauri::command]
pub fn start_file_search(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: StartFileSearch,
) -> Result<Uuid, IpcError> {
    let (_, checkout) = capture_file_scope(&window, &project, &request.scope)?;
    if request.query.trim().is_empty() || request.query.len() > 1024 || request.mask.len() > 256 {
        return Err(IpcError::ProjectUnavailable);
    }
    let mut state = project.state.lock().expect("workspace state lock poisoned");
    if state.projection.visible_file_tools_scope().as_ref() != Some(&request.scope) {
        return Err(IpcError::StaleSelection);
    }
    state.retire_file_search();
    let id = Uuid::new_v4();
    state.file_search = Some(Arc::new(FileSearchSession {
        id,
        scope: request.scope,
        checkout,
        query: request.query,
        mask: request.mask,
        canceled: AtomicBool::new(false),
        scan: Arc::default(),
    }));
    Ok(id)
}

#[tauri::command]
pub async fn read_file_search(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ReadFileSearch,
) -> Result<FileSearchPage, IpcError> {
    let session = current_session(&window, &project, request.session)?;
    let mut scan = session
        .scan
        .clone()
        .try_lock_owned()
        .map_err(|_| IpcError::StaleSelection)?;
    if scan.finished || scan.cursor != request.cursor {
        return Err(IpcError::StaleSelection);
    }
    if scan.reader.is_none() {
        let cache = project.path_index(window.label(), session.scope.workspace_id)?;
        let mut index = cache.lock_owned().await;
        current_session(&window, &project, request.session)?;
        let candidates = tauri::async_runtime::spawn_blocking(move || index.content_candidates())
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?
            .map_err(index_error)?;
        scan.reader = Some(
            FileContentSearch::new(
                session.checkout.clone(),
                candidates,
                session.query.clone(),
                &session.mask,
            )
            .map_err(search_error)?,
        );
    }
    let page = tauri::async_runtime::spawn_blocking(move || {
        let page = scan
            .reader
            .as_mut()
            .expect("file search initialized")
            .next(&session.canceled)
            .map_err(search_error)?;
        scan.cursor = page.more.then(Uuid::new_v4);
        scan.finished = !page.more;
        let mut matches = Vec::with_capacity(page.matches.len());
        for item in page.matches {
            matches.push(FileSearchResult {
                id: item.id,
                path: item.path().to_owned(),
                line: item.line,
                excerpt: item.excerpt.clone(),
            });
            scan.matches.insert(item.id, item);
        }
        Ok::<FileSearchPage, IpcError>(FileSearchPage {
            matches,
            next_cursor: scan.cursor,
        })
    })
    .await
    .map_err(|_| IpcError::ProjectUnavailable)??;
    current_session(&window, &project, request.session)?;
    Ok(page)
}

#[tauri::command]
pub fn cancel_file_search(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    session: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let mut state = project.state.lock().expect("workspace state lock poisoned");
    if state
        .file_search
        .as_ref()
        .is_some_and(|active| active.id == session)
    {
        state.retire_file_search();
    }
    Ok(())
}

#[tauri::command]
pub async fn open_file_search_hit(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: OpenFileSearchHit,
) -> Result<OpenedFileSearchHit, IpcError> {
    let session = current_session(&window, &project, request.session)?;
    let hit = session
        .scan
        .try_lock()
        .map_err(|_| IpcError::StaleSelection)?
        .matches
        .get(&request.id)
        .cloned()
        .ok_or(IpcError::StaleSelection)?;
    let file = tauri::async_runtime::spawn_blocking(move || hit.prepare_open())
        .await
        .map_err(|_| IpcError::ProjectUnavailable)?
        .map_err(|error| match error {
            FileError::Checkout(_) => IpcError::RetiredWorkspace,
            _ => IpcError::StaleSelection,
        })?;
    let (navigation, _) = capture_file_scope(&window, &project, &session.scope)?;
    navigation
        .open_file_search_hit(PreparedFileHit { session, file })
        .await
}

fn current_session(
    window: &WebviewWindow,
    project: &ProjectIpc,
    id: Uuid,
) -> Result<Arc<FileSearchSession>, IpcError> {
    authorize_view(window)?;
    let state = project.state.lock().expect("workspace state lock poisoned");
    let session = state
        .file_search
        .as_ref()
        .filter(|session| session.id == id)
        .ok_or(IpcError::StaleSelection)?;
    if state.projection.visible_file_tools_scope().as_ref() != Some(&session.scope)
        || session.canceled.load(Ordering::Acquire)
    {
        return Err(IpcError::StaleSelection);
    }
    state
        .grants
        .checkout(window.label(), session.scope.workspace_id)?;
    Ok(session.clone())
}

fn search_error(error: ContentSearchError) -> IpcError {
    match error {
        ContentSearchError::Canceled => IpcError::StaleSelection,
        ContentSearchError::Checkout(_) => IpcError::RetiredWorkspace,
        ContentSearchError::InvalidQuery => IpcError::ProjectUnavailable,
    }
}
