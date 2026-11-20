use std::{
    fs::{self, File},
    io::{self, BufReader},
    path::Path,
};

use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;
use ts_rs::TS;
use uuid::Uuid;

use crate::checkout::{CheckoutError, CheckoutIdentity};

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContext {
    #[serde(default)]
    pub items: Vec<ProjectContextItem>,
    #[serde(default)]
    pub saved_prompts: Vec<SavedPrompt>,
    #[serde(rename = "selectedPromptID")]
    pub selected_prompt_id: Option<String>,
    pub selected_skill: Option<ProjectSkillSelection>,
    pub model_preference: Option<ProjectModelPreference>,
    #[serde(default)]
    pub bookmarks: Vec<ConversationBookmark>,
}

impl ProjectContext {
    pub fn has_submission_context(&self) -> bool {
        self.selected_skill.is_some() || self.items.iter().any(|item| item.is_included)
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextItem {
    pub id: String,
    pub kind: ProjectContextItemKind,
    pub title: String,
    pub body: String,
    pub reference_path: Option<String>,
    pub is_included: bool,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ProjectContextItemKind {
    Specification,
    ReferenceFile,
    Note,
    Decision,
}

impl ProjectContextItem {
    pub fn request_text(&self) -> String {
        let kind = match self.kind {
            ProjectContextItemKind::Specification => "specification",
            ProjectContextItemKind::ReferenceFile => "referenceFile",
            ProjectContextItemKind::Note => "note",
            ProjectContextItemKind::Decision => "decision",
        };
        let mut text = format!("[{kind}] {}", self.title);
        if let Some(path) = self
            .reference_path
            .as_deref()
            .filter(|path| !path.is_empty())
        {
            text.push_str("\nFile: ");
            text.push_str(path);
        }
        if !self.body.is_empty() {
            text.push('\n');
            text.push_str(&self.body);
        }
        text
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
pub struct SavedPrompt {
    pub id: String,
    pub title: String,
    pub instructions: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
pub struct ProjectSkillSelection {
    pub name: String,
    pub description: String,
    pub path: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
pub struct ProjectModelPreference {
    #[serde(rename = "modelID")]
    pub model_id: Option<String>,
    pub effort: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ConversationBookmark {
    pub id: String,
    #[serde(rename = "threadID")]
    pub thread_id: String,
    #[serde(rename = "turnID")]
    pub turn_id: String,
    #[serde(rename = "itemID")]
    pub item_id: Option<String>,
    pub kind: ConversationBookmarkKind,
    pub label: String,
    pub file_path: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ConversationBookmarkKind {
    UserRequest,
    Answer,
    Decision,
    ChangedFile,
    Failure,
}

#[derive(Debug, Default, Serialize, TS)]
pub struct ProjectContextView {
    pub revision: u32,
    pub context: ProjectContext,
}

#[derive(Debug, Eq, PartialEq)]
pub enum ProjectContextImport {
    Imported,
    PreservedDestination,
    MissingSource,
}

#[derive(Debug, Error)]
pub enum ProjectContextError {
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Database(#[from] rusqlite::Error),
    #[error(transparent)]
    Disk(#[from] io::Error),
    #[error(transparent)]
    Document(#[from] serde_json::Error),
    #[error("the project path cannot be represented in the AppKit format")]
    NonUnicodePath,
    #[error("the AppKit project context has unsupported version {0}")]
    UnsupportedVersion(u64),
    #[error("the AppKit project context belongs to a different checkout")]
    WrongProject,
    #[error("the copied AppKit context is not a regular file")]
    InvalidSource,
    #[error("the project context was edited or its checkout changed")]
    StaleRevision,
    #[error("the project context edit is invalid")]
    InvalidEdit,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppKitDocument {
    version: u64,
    project_path: String,
    context: serde_json::Value,
}

pub(super) fn staged_appkit_projects(
    copied_context_directory: &Path,
) -> Result<Vec<String>, ProjectContextError> {
    let entries = match fs::read_dir(copied_context_directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    let mut paths = Vec::new();
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name();
        let Some(digest) = name.to_str().and_then(|name| name.strip_suffix(".json")) else {
            continue;
        };
        if digest.len() != 64 || !digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            continue;
        }
        let metadata = fs::symlink_metadata(entry.path())?;
        if !metadata.is_file() || metadata.len() > 32 * 1024 * 1024 {
            return Err(ProjectContextError::InvalidSource);
        }
        let document: AppKitDocument =
            serde_json::from_reader(BufReader::new(File::open(entry.path())?))?;
        if name.to_str() != Some(appkit_file_name(&document.project_path).as_str()) {
            return Err(ProjectContextError::WrongProject);
        }
        paths.push(document.project_path);
    }
    paths.sort();
    Ok(paths)
}

pub fn import_appkit_project_context(
    database: &mut Connection,
    copied_context_directory: &Path,
    checkout: &CheckoutIdentity,
) -> Result<ProjectContextImport, ProjectContextError> {
    checkout.revalidate()?;
    let path = project_path(checkout)?;
    let document_path = copied_context_directory.join(appkit_file_name(path));
    match fs::symlink_metadata(&document_path) {
        Ok(metadata) if metadata.is_file() => {}
        Ok(_) => return Err(ProjectContextError::InvalidSource),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(ProjectContextImport::MissingSource);
        }
        Err(error) => return Err(error.into()),
    }
    let document: AppKitDocument =
        serde_json::from_reader(BufReader::new(File::open(document_path)?))?;
    if document.version != 1 {
        return Err(ProjectContextError::UnsupportedVersion(document.version));
    }
    if document.project_path != path {
        return Err(ProjectContextError::WrongProject);
    }
    let context: ProjectContext = serde_json::from_value(document.context)?;
    let inserted = initialize_project_context(database, checkout, &context)?;
    Ok(if inserted {
        ProjectContextImport::Imported
    } else {
        ProjectContextImport::PreservedDestination
    })
}

pub fn initialize_project_context(
    database: &mut Connection,
    checkout: &CheckoutIdentity,
    context: &ProjectContext,
) -> Result<bool, ProjectContextError> {
    let content = serde_json::to_string(context)?;
    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    checkout.revalidate()?;
    let inserted = transaction.execute(
        "INSERT INTO project_contexts (checkout_path, checkout_key, content) VALUES (?1, ?2, ?3)
         ON CONFLICT (checkout_path) DO NOTHING",
        params![project_path(checkout)?, checkout.storage_key(), content],
    )?;
    transaction.commit()?;
    Ok(inserted == 1)
}

pub fn read_project_context(
    database: &Connection,
    checkout: &CheckoutIdentity,
) -> Result<Option<ProjectContext>, ProjectContextError> {
    Ok(project_context_view(database, checkout)?.map(|view| view.context))
}

pub fn project_context_view(
    database: &Connection,
    checkout: &CheckoutIdentity,
) -> Result<Option<ProjectContextView>, ProjectContextError> {
    checkout.revalidate()?;
    let row: Option<(u32, String)> = database
        .query_row(
            "SELECT revision, content FROM project_contexts WHERE checkout_path = ?1 AND checkout_key = ?2",
            params![project_path(checkout)?, checkout.storage_key()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    row.map(|(revision, content)| {
        Ok(ProjectContextView {
            revision,
            context: serde_json::from_str(&content)?,
        })
    })
    .transpose()
}

pub fn edit_project_context(
    database: &mut Connection,
    checkout: &CheckoutIdentity,
    revision: u32,
    edit: impl FnOnce(&mut ProjectContext) -> Result<(), ProjectContextError>,
) -> Result<ProjectContextView, ProjectContextError> {
    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let mut view = project_context_view(&transaction, checkout)?.unwrap_or_default();
    if view.revision != revision {
        return Err(ProjectContextError::StaleRevision);
    }
    edit(&mut view.context)?;
    let next = revision
        .checked_add(1)
        .ok_or(ProjectContextError::InvalidEdit)?;
    let content = serde_json::to_string(&view.context)?;
    let changed = transaction.execute(
        "INSERT INTO project_contexts (checkout_path, checkout_key, content, revision)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (checkout_path) DO UPDATE SET content = excluded.content, revision = excluded.revision
         WHERE project_contexts.checkout_key = excluded.checkout_key",
        params![project_path(checkout)?, checkout.storage_key(), content, next],
    )?;
    if changed != 1 {
        return Err(ProjectContextError::StaleRevision);
    }
    transaction.commit()?;
    view.revision = next;
    Ok(view)
}

pub fn put_project_entry<T>(
    entries: &mut Vec<T>,
    id: Option<String>,
    identity: impl Fn(&T) -> &str,
    value: impl FnOnce(String) -> T,
) -> Result<(), ProjectContextError> {
    if let Some(id) = id {
        let entry = entries
            .iter_mut()
            .find(|entry| identity(entry) == id)
            .ok_or(ProjectContextError::StaleRevision)?;
        *entry = value(id);
    } else {
        entries.push(value(Uuid::new_v4().to_string()));
    }
    Ok(())
}

pub fn remove_project_entry<T>(
    entries: &mut Vec<T>,
    id: &str,
    identity: impl Fn(&T) -> &str,
) -> Result<(), ProjectContextError> {
    let index = entries
        .iter()
        .position(|entry| identity(entry) == id)
        .ok_or(ProjectContextError::StaleRevision)?;
    entries.remove(index);
    Ok(())
}

fn project_path(checkout: &CheckoutIdentity) -> Result<&str, ProjectContextError> {
    checkout
        .canonical_path()
        .to_str()
        .ok_or(ProjectContextError::NonUnicodePath)
}

fn appkit_file_name(path: &str) -> String {
    format!("{}.json", hex::encode(Sha256::digest(path.as_bytes())))
}

pub(super) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE project_contexts (
            checkout_path TEXT PRIMARY KEY NOT NULL,
            checkout_key TEXT NOT NULL,
            content TEXT NOT NULL CHECK (json_valid(content) AND json_type(content) = 'object')
        ) STRICT, WITHOUT ROWID;",
    )
}

pub(super) fn migrate_revisions(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "ALTER TABLE project_contexts ADD COLUMN revision INTEGER NOT NULL DEFAULT 1",
    )
}

#[cfg(test)]
mod tests;
