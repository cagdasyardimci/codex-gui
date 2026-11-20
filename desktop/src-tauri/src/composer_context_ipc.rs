use std::{path::Path, time::Duration};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::CodexBrowser,
    files::CheckoutFiles,
    identity::ConnectionIdentity,
    ipc::{
        ComposerChoice, ComposerChoiceKind, ComposerContextSelection, ComposerContextTarget,
        ComposerSourceLines, ComposerTokenRange, DraftAttachmentScope, IpcError,
    },
    storage::project_context::{ProjectContextView, ProjectSkillSelection},
};
use serde_json::{Value, json};
use tauri::{State, WebviewWindow};
use uuid::Uuid;

use crate::{
    composer_ipc::capture, fixture::Verification, navigation::ComposerAttachmentMutation,
    project_ipc::ProjectIpc,
};

const MAX_CATALOG_ENTRIES: usize = 128;
const MAX_EXCERPT_BYTES: usize = 16 * 1024;
const MAX_NOTE_BYTES: usize = 64 * 1024;

pub(crate) struct ComposerCatalog {
    scope: DraftAttachmentScope,
    connection: Option<ConnectionIdentity>,
    entries: Vec<(ComposerChoice, Value)>,
}

impl ComposerCatalog {
    pub(crate) fn skill(
        &self,
        scope: &DraftAttachmentScope,
        connection: Option<&ConnectionIdentity>,
        id: Uuid,
    ) -> Option<ProjectSkillSelection> {
        if scope != &self.scope || connection != self.connection.as_ref() {
            return None;
        }
        let (_, value) = self
            .entries
            .iter()
            .find(|(choice, _)| choice.id == id && choice.kind == ComposerChoiceKind::Skill)?;
        Some(ProjectSkillSelection {
            name: value["title"].as_str()?.into(),
            path: Some(value["path"].as_str()?.into()),
            description: value["description"].as_str().unwrap_or_default().into(),
        })
    }
}

#[tauri::command]
pub fn read_project_context(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    scope: DraftAttachmentScope,
) -> Result<ProjectContextView, IpcError> {
    let (navigation, checkout) = capture(&window, &project, &scope)?;
    navigation
        .attachment_store()
        .project_context_view(&checkout)
        .map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub fn seed_composer_context_fixture(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    scope: DraftAttachmentScope,
) -> Result<(), IpcError> {
    if !matches!(
        *verification,
        Verification::ComposerContext | Verification::ProjectContext
    ) {
        return Err(IpcError::UnauthorizedWindow);
    }
    use codex_gui_core::storage::project_context::{
        ConversationBookmark, ConversationBookmarkKind, ProjectContext, ProjectContextItem,
        ProjectContextItemKind,
    };
    let (navigation, checkout) = capture(&window, &project, &scope)?;
    let mut context = ProjectContext::default();
    if *verification == Verification::ProjectContext {
        context.bookmarks.push(ConversationBookmark {
            id: "fixture-bookmark".into(),
            thread_id: "history-first".into(),
            turn_id: "first-saved-turn".into(),
            item_id: Some("first-history".into()),
            kind: ConversationBookmarkKind::Answer,
            label: "Original fixture response".into(),
            file_path: None,
        });
    } else {
        context.items.push(ProjectContextItem {
            id: "fixture-note".into(),
            kind: ProjectContextItemKind::Note,
            title: "Project note".into(),
            body: "Use the local fixture only.".into(),
            reference_path: None,
            is_included: true,
        });
    }
    navigation
        .attachment_store()
        .initialize_composer_project_context(&checkout, &context)
        .map(|_| ())
        .map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub async fn composer_context_catalog(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    scope: DraftAttachmentScope,
) -> Result<Vec<ComposerChoice>, IpcError> {
    let (navigation, checkout) = capture(&window, &project, &scope)?;
    let context = navigation
        .attachment_store()
        .composer_project_context(&checkout)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    let client = navigation.composer_context_client(scope.clone()).await?;
    let mut entries = Vec::new();
    if let Some(client) = &client {
        let read = CodexBrowser::new(client.clone())
            .composer_skills(Duration::from_secs(4))
            .await;
        if let Ok(skills) = read {
            for skill in skills.into_iter().take(MAX_CATALOG_ENTRIES) {
                let choice = ComposerChoice {
                    id: Uuid::new_v4(),
                    label: skill.name,
                    kind: ComposerChoiceKind::Skill,
                };
                let value = json!({"kind": "skill", "title": choice.label, "path": skill.path,
                    "description": skill.description});
                entries.push((choice, value));
            }
        }
    }
    if let Some(context) = context {
        let available = MAX_CATALOG_ENTRIES.saturating_sub(entries.len());
        for note in context
            .items
            .into_iter()
            .filter(|item| item.is_included && item.body.len() <= MAX_NOTE_BYTES)
            .take(available)
        {
            let choice = ComposerChoice {
                id: Uuid::new_v4(),
                label: note.title,
                kind: ComposerChoiceKind::ProjectContext,
            };
            let value = json!({"kind": "projectContext", "title": choice.label, "body": note.body, "projectItemId": note.id});
            entries.push((choice, value));
        }
    }
    capture(&window, &project, &scope)?;
    let connection = client.map(|client| client.identity().clone());
    let current = navigation.composer_context_client(scope.clone()).await?;
    if current.as_ref().map(|client| client.identity()) != connection.as_ref() {
        return Err(IpcError::StaleSelection);
    }
    let choices = entries.iter().map(|(choice, _)| choice.clone()).collect();
    project
        .state
        .lock()
        .expect("workspace state lock poisoned")
        .composer_catalog = Some(ComposerCatalog {
        scope,
        connection,
        entries,
    });
    Ok(choices)
}

#[tauri::command]
pub async fn add_composer_context(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    request: ComposerContextSelection,
) -> Result<(), IpcError> {
    let (navigation, checkout) = capture(&window, &project, &request.scope)?;
    let text = match request.replace_token {
        Some(range) => {
            remove_token(&request.expected_text, range).ok_or(IpcError::StaleSelection)?
        }
        None => request.expected_text.clone(),
    };
    let mut item = match request.target {
        ComposerContextTarget::Catalog(id) => {
            let (connection, value) = {
                let state = project.state.lock().expect("workspace state lock poisoned");
                let catalog = state
                    .composer_catalog
                    .as_ref()
                    .filter(|catalog| catalog.scope == request.scope)
                    .ok_or(IpcError::StaleSelection)?;
                let (_, value) = catalog
                    .entries
                    .iter()
                    .find(|(choice, _)| choice.id == id)
                    .ok_or(IpcError::StaleSelection)?;
                (catalog.connection.clone(), value.clone())
            };
            if value["kind"] == "skill" {
                let client = navigation
                    .composer_context_client(request.scope.clone())
                    .await?;
                if client.as_ref().map(|client| client.identity()) != connection.as_ref() {
                    return Err(IpcError::StaleSelection);
                }
            }
            value
        }
        ComposerContextTarget::File(file) => {
            let index = project
                .path_index(window.label(), request.scope.workspace_id)?
                .lock_owned()
                .await;
            tauri::async_runtime::spawn_blocking(move || {
                let mut index = index;
                let path = index
                    .resolve(file.path)
                    .map_err(|_| IpcError::StaleSelection)?;
                file_context(checkout, &path, file.lines)
            })
            .await
            .map_err(|_| IpcError::ProjectUnavailable)??
        }
    };
    item["id"] = json!(Uuid::new_v4());
    capture(&window, &project, &request.scope)?;
    navigation
        .mutate_attachments(ComposerAttachmentMutation::Context {
            scope: request.scope,
            expected: request.expected_text,
            text,
            item,
        })
        .await
}

fn file_context(
    checkout: CheckoutIdentity,
    relative: &Path,
    range: Option<ComposerSourceLines>,
) -> Result<Value, IpcError> {
    let mut files = CheckoutFiles::new(checkout);
    let link = files
        .issue(relative)
        .map_err(|_| IpcError::StaleSelection)?;
    let name = relative
        .file_name()
        .and_then(|path| path.to_str())
        .ok_or(IpcError::StaleSelection)?;
    let path = relative.to_str().ok_or(IpcError::StaleSelection)?;
    let Some(range) = range else {
        return Ok(json!({"kind": "fileReference", "title": name, "path": path}));
    };
    let count = range
        .last
        .checked_sub(range.first)
        .and_then(|count| count.checked_add(1))
        .filter(|count| range.first > 0 && *count <= 128)
        .ok_or(IpcError::StaleSelection)?;
    let read = files
        .read(link.id)
        .map_err(|_| IpcError::ProjectUnavailable)?;
    let text = std::str::from_utf8(&read.bytes).map_err(|_| IpcError::ProjectUnavailable)?;
    let lines: Vec<_> = text
        .lines()
        .skip(range.first as usize - 1)
        .take(count as usize)
        .collect();
    if lines.len() != count as usize {
        return Err(IpcError::StaleSelection);
    }
    let excerpt = lines.join("\n");
    if excerpt.len() > MAX_EXCERPT_BYTES {
        return Err(IpcError::ProjectUnavailable);
    }
    Ok(
        json!({ "kind": "textExcerpt", "title": format!("{name}:{}–{}", range.first, range.last),
        "path": path, "excerpt": excerpt, "firstLine": range.first, "lastLine": range.last }),
    )
}

fn remove_token(source: &str, range: ComposerTokenRange) -> Option<String> {
    let start = utf16_boundary(source, range.start)?;
    let end = utf16_boundary(source, range.end)?;
    let token = source.get(start..end)?;
    if !token.starts_with('@')
        || token.chars().any(char::is_whitespace)
        || source[..start]
            .chars()
            .next_back()
            .is_some_and(|value| !value.is_whitespace())
        || source[end..]
            .chars()
            .next()
            .is_some_and(|value| !value.is_whitespace())
    {
        return None;
    }
    let mut replaced = source.to_owned();
    replaced.replace_range(start..end, "");
    Some(replaced)
}

fn utf16_boundary(source: &str, offset: u32) -> Option<usize> {
    let mut units = 0;
    for (index, value) in source.char_indices() {
        if units == offset {
            return Some(index);
        }
        units += value.len_utf16() as u32;
        if units > offset {
            return None;
        }
    }
    (units == offset).then_some(source.len())
}
