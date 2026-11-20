use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{FileRevision, comparison_file_revision},
    git::{CheckoutDiff, ComparisonSpec, GitComparisons, GitError},
    ipc::{
        ChatRequest, DiffChangesRequest, DiffComparison, DiffFileView, DiffMarkerRequest,
        DiffPatchRequest, DiffPatchView, DiffReference, DiffReferences, DiffSide,
        DraftAttachmentScope, FileEditor, IpcError,
    },
    storage::attachments::AttachmentStore,
};
use tauri::{State, WebviewWindow};
use uuid::Uuid;

use crate::{
    file_actions_ipc::editors,
    file_tools_ipc::capture_file_scope,
    fixture::Verification,
    navigation::NavigationHandle,
    project_ipc::{ProjectIpc, authorize_view},
};

pub(crate) mod actions;
mod capture;

use capture::{Candidate, Capture, Source};

#[derive(Default)]
pub struct DiffIpc {
    state: Mutex<QueryState>,
    repository: Mutex<Option<(CheckoutIdentity, GitComparisons)>>,
    editor_directory: Mutex<Option<tempfile::TempDir>>,
}

#[derive(Default)]
struct QueryState {
    query: Uuid,
    view: Option<(DraftAttachmentScope, Uuid)>,
    detail: Uuid,
    published: Option<Arc<Scope>>,
    selection: Option<Arc<Selection>>,
}

struct Scope {
    shown: DraftAttachmentScope,
    origin: String,
    checkout: CheckoutIdentity,
    report: Option<Uuid>,
    files: HashMap<String, Candidate>,
}

struct Selection {
    file_id: String,
    path: String,
    capture: Capture,
}

impl DiffIpc {
    async fn repository(&self, checkout: CheckoutIdentity) -> Result<GitComparisons, IpcError> {
        if let Some((_, git)) = self
            .repository
            .lock()
            .expect("repository lock poisoned")
            .as_ref()
            .filter(|(owner, _)| owner == &checkout)
        {
            return Ok(git.clone());
        }
        let git = GitComparisons::open(checkout.clone())
            .await
            .map_err(report)?;
        *self.repository.lock().expect("repository lock poisoned") = Some((checkout, git.clone()));
        Ok(git)
    }

    fn get_scope(&self, shown: &DraftAttachmentScope) -> Result<Arc<Scope>, IpcError> {
        self.state
            .lock()
            .expect("changes query lock poisoned")
            .published
            .as_ref()
            .filter(|scope| &scope.shown == shown)
            .cloned()
            .ok_or(IpcError::StaleSelection)
    }

    fn get_selected(
        &self,
        target: &DiffPatchRequest,
    ) -> Result<(Arc<Scope>, Arc<Selection>), IpcError> {
        let state = self.state.lock().expect("changes query lock poisoned");
        let scope = state
            .published
            .as_ref()
            .filter(|scope| scope.shown == target.scope)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        let selection = state
            .selection
            .as_ref()
            .filter(|selection| selection.file_id == target.file_id)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        Ok((scope, selection))
    }
}

#[tauri::command]
pub async fn checkout_diff_references(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    scope: DraftAttachmentScope,
) -> Result<DiffReferences, IpcError> {
    let (_, checkout) = capture_file_scope(&window, &project, &scope)?;
    let git = state.repository(checkout).await?;
    let branches = git.branches().await.map_err(report)?;
    let commits = git.recent_commits().await.map_err(report)?;
    capture_file_scope(&window, &project, &scope)?;
    Ok(DiffReferences {
        upstream: branches.upstream,
        branches: branches
            .choices
            .into_iter()
            .map(|branch| DiffReference {
                reference: branch.reference,
                label: branch.label,
            })
            .collect(),
        commits: commits
            .into_iter()
            .map(|commit| DiffReference {
                label: format!("{} {}", &commit.oid[..8], commit.subject),
                reference: commit.oid,
            })
            .collect(),
    })
}

#[tauri::command]
pub async fn checkout_changes(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: DiffChangesRequest,
) -> Result<Vec<DiffFileView>, IpcError> {
    let (navigation, checkout) = capture_file_scope(&window, &project, &request.scope)?;
    let query = Uuid::new_v4();
    {
        let mut state = state.state.lock().expect("changes query lock poisoned");
        *state = QueryState {
            query,
            view: Some((request.scope.clone(), request.view_id)),
            ..Default::default()
        };
    }
    let root =
        FileRevision::from_bytes(checkout.canonical_path().as_os_str().as_encoded_bytes()).digest;
    let (origin, revision, candidates) = if request.comparison == DiffComparison::LastTurn {
        let result = navigation.last_turn_changes(request.scope.clone()).await?;
        let candidates = result
            .iter()
            .flat_map(|edits| {
                edits.files.iter().enumerate().filter_map(|(index, file)| {
                    let path = file
                        .after
                        .as_ref()
                        .or(file.before.as_ref())?
                        .to_string_lossy()
                        .into_owned();
                    let renamed_from = file
                        .before
                        .as_ref()
                        .filter(|before| file.after.as_ref().is_some_and(|after| after != *before))
                        .map(|path| path.to_string_lossy().into_owned());
                    Some(Candidate {
                        path,
                        renamed_from,
                        source: Source::Reported(edits.clone(), index),
                    })
                })
            })
            .collect::<Vec<_>>();
        let view = result.as_ref().map(|edits| edits.view());
        (
            serde_json::json!([root, request.scope.chat_id, view.map(|view| &view.turn_id)])
                .to_string(),
            view.and_then(|view| view.revision),
            candidates,
        )
    } else {
        let (spec, untracked) = match request.comparison.clone() {
            DiffComparison::Uncommitted => (ComparisonSpec::Uncommitted, true),
            DiffComparison::Staged => (ComparisonSpec::Staged, false),
            DiffComparison::Unstaged => (ComparisonSpec::Unstaged, true),
            DiffComparison::Branch(branch) => {
                (ComparisonSpec::WorkingTreeAgainstBranch(branch), true)
            }
            DiffComparison::Commit(commit) => (ComparisonSpec::Commit(commit), false),
            DiffComparison::Between { base, target } => {
                if base.len() > 512 || target.len() > 512 {
                    return Err(IpcError::StaleSelection);
                }
                (ComparisonSpec::Between { base, target }, false)
            }
            DiffComparison::LastTurn => unreachable!(),
        };
        let git = state.repository(checkout.clone()).await?;
        let comparison = Arc::new(git.compare(spec).await.map_err(report)?);
        let origin = serde_json::json!([root, format!("{:?}", comparison.sides())]).to_string();
        let mut files = comparison
            .files()
            .filter_map(|file| {
                let path = file.after.clone().or_else(|| file.before.clone())?;
                let renamed_from = if file.after.is_some() && file.before != file.after {
                    file.before
                } else {
                    None
                };
                Some(Candidate {
                    path,
                    renamed_from,
                    source: Source::Tracked(comparison.clone(), file.id),
                })
            })
            .collect::<Vec<_>>();
        if untracked {
            let legacy = Arc::new(CheckoutDiff::open(checkout.clone()).await.map_err(report)?);
            let entries = legacy.untracked().await.map_err(report)?;
            let indexed = checkout.clone();
            let loose = tauri::async_runtime::spawn_blocking(move || {
                let mut remaining = 32 * 1024 * 1024_u64;
                entries
                    .into_iter()
                    .map(|file| {
                        let revision =
                            comparison_file_revision(&indexed, file.relative(), remaining).ok();
                        remaining -= revision.as_ref().map_or(0, |stamp| stamp.byte_count as u64);
                        Candidate {
                            path: file.display_path(),
                            renamed_from: None,
                            source: Source::Untracked(legacy.clone(), file, revision),
                        }
                    })
                    .collect::<Vec<_>>()
            })
            .await
            .map_err(|_| IpcError::ProjectUnavailable)?;
            files.extend(loose);
        }
        (origin, None, files)
    };
    capture_file_scope(&window, &project, &request.scope)?;
    let mut state = state.state.lock().expect("changes query lock poisoned");
    if state.query != query {
        return Err(IpcError::StaleSelection);
    }
    let mut files = HashMap::with_capacity(candidates.len());
    let mut view = Vec::with_capacity(candidates.len());
    for file in candidates {
        let file_id = Uuid::new_v4().to_string();
        view.push(file.view(file_id.clone()));
        files.insert(file_id, file);
    }
    view.sort_by(|a, b| a.path.cmp(&b.path));
    state.published = Some(Arc::new(Scope {
        shown: request.scope,
        origin,
        checkout,
        report: revision,
        files,
    }));
    Ok(view)
}

#[tauri::command]
pub fn close_checkout_changes(
    window: WebviewWindow,
    state: State<'_, DiffIpc>,
    scope: DraftAttachmentScope,
    view_id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let mut query = state.state.lock().expect("changes query lock poisoned");
    if query.view.as_ref() == Some(&(scope, view_id)) {
        *query = QueryState::default();
    }
    Ok(())
}

#[tauri::command]
pub async fn checkout_patch(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    verification: State<'_, Verification>,
    request: DiffPatchRequest,
) -> Result<DiffPatchView, IpcError> {
    capture_file_scope(&window, &project, &request.scope)?;
    let scope = state.get_scope(&request.scope)?;
    let candidate = scope
        .files
        .get(&request.file_id)
        .ok_or(IpcError::StaleSelection)?;
    let detail = Uuid::new_v4();
    {
        let mut query = state.state.lock().expect("changes query lock poisoned");
        if !query
            .published
            .as_ref()
            .is_some_and(|published| Arc::ptr_eq(published, &scope))
        {
            return Err(IpcError::StaleSelection);
        }
        query.detail = detail;
        query.selection = None;
    }
    let capture = candidate
        .capture(&scope.checkout, &scope.origin)
        .await
        .map_err(report)?;
    let navigation = validate_scope(&window, &project, &scope).await?;
    let mut query = state.state.lock().expect("changes query lock poisoned");
    if query.detail != detail {
        return Err(IpcError::StaleSelection);
    }
    let view = patch_view(
        navigation.attachment_store(),
        &request.file_id,
        &capture,
        *verification,
    )?;
    query.selection = Some(Arc::new(Selection {
        file_id: request.file_id,
        path: candidate.path.clone(),
        capture,
    }));
    Ok(view)
}

#[tauri::command]
pub async fn mark_checkout_change(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    state: State<'_, DiffIpc>,
    request: DiffMarkerRequest,
) -> Result<(), IpcError> {
    let (scope, selection) = state.get_selected(&request.target)?;
    let navigation = validate_scope(&window, &project, &scope).await?;
    let current = state.get_selected(&request.target)?.1;
    if !Arc::ptr_eq(&selection, &current) {
        return Err(IpcError::StaleSelection);
    }
    let index = request.hunk.map_or(-1, i64::from);
    let fingerprint = selection
        .capture
        .fingerprint(index)
        .ok_or(IpcError::StaleSelection)?;
    navigation
        .attachment_store()
        .set_review_marker(
            &selection.capture.marker_origin,
            index,
            fingerprint,
            request.reviewed,
        )
        .map_err(storage_error)
}

async fn validate_scope(
    window: &WebviewWindow,
    project: &ProjectIpc,
    scope: &Scope,
) -> Result<NavigationHandle, IpcError> {
    let (navigation, checkout) = capture_file_scope(window, project, &scope.shown)?;
    if scope.checkout != checkout {
        return Err(IpcError::StaleSelection);
    }
    if let Some(revision) = scope.report
        && navigation
            .last_turn_changes(scope.shown.clone())
            .await?
            .and_then(|edits| edits.view().revision)
            != Some(revision)
    {
        return Err(IpcError::StaleSelection);
    }
    capture_file_scope(window, project, &scope.shown)?;
    Ok(navigation)
}

fn patch_view(
    store: &AttachmentStore,
    file_id: &str,
    capture: &Capture,
    verification: Verification,
) -> Result<DiffPatchView, IpcError> {
    let markers = store
        .review_markers(&capture.marker_origin)
        .map_err(storage_error)?;
    let mut reviewed = false;
    let mut reviewed_hunks = Vec::new();
    for (index, fingerprint) in markers {
        if capture.fingerprint(index) == Some(fingerprint.as_str()) {
            if index == -1 {
                reviewed = true;
            }
            if let Ok(hunk) = u32::try_from(index) {
                reviewed_hunks.push(hunk);
            }
        }
    }
    let available = if verification == Verification::Diff {
        vec![FileEditor {
            id: "vscode".to_owned(),
            label: "VS Code".to_owned(),
        }]
    } else {
        editors::installed()
            .iter()
            .map(editors::Editor::view)
            .collect()
    };
    let contents = [DiffSide::Before, DiffSide::After]
        .into_iter()
        .filter_map(|side| {
            capture
                .contents(side)
                .map(|content| content.view(side, available.clone()))
        })
        .collect();
    Ok(DiffPatchView {
        file_id: file_id.to_owned(),
        text: String::from_utf8_lossy(&capture.patch).into_owned(),
        exportable: capture.patch_exportable,
        reviewed,
        reviewed_hunks,
        contents,
    })
}

#[tauri::command]
pub async fn count_chat_changes(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ChatRequest,
) -> Result<u32, IpcError> {
    authorize_view(&window)?;
    let checkout = project.checkout(window.label(), request.workspace_id)?;
    require_chat(&project, &request)?;
    let checkout = CheckoutDiff::open(checkout).await.map_err(report)?;
    let count = checkout.changes().await.map_err(report)?.len();
    authorize_view(&window)?;
    project.checkout(window.label(), request.workspace_id)?;
    require_chat(&project, &request)?;
    u32::try_from(count).map_err(|_| IpcError::ProjectUnavailable)
}

fn require_chat(project: &ProjectIpc, request: &ChatRequest) -> Result<(), IpcError> {
    project
        .state
        .lock()
        .expect("workspace state lock poisoned")
        .projection
        .read_conversation(request.workspace_id, &request.chat_id, |_| ())
}

fn report(error: GitError) -> IpcError {
    match error {
        GitError::StaleComparison | GitError::RetiredFile => IpcError::StaleSelection,
        error => {
            eprintln!("{error}");
            IpcError::ProjectUnavailable
        }
    }
}

fn storage_error(error: codex_gui_core::storage::attachments::AttachmentError) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}

fn captured_name(path: &str) -> Result<&Path, IpcError> {
    Path::new(path)
        .file_name()
        .map(Path::new)
        .ok_or(IpcError::StaleSelection)
}
