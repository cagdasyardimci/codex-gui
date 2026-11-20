use std::{
    fs::{self, File},
    io::{self, BufReader},
    path::Path,
};

use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::checkout::{CheckoutError, CheckoutIdentity};

#[derive(Debug, Default, Deserialize, PartialEq, Serialize)]
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

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextItem {
    pub id: String,
    pub kind: ProjectContextItemKind,
    pub title: String,
    pub body: String,
    pub reference_path: Option<String>,
    pub is_included: bool,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProjectContextItemKind {
    Specification,
    ReferenceFile,
    Note,
    Decision,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct SavedPrompt {
    pub id: String,
    pub title: String,
    pub instructions: String,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct ProjectSkillSelection {
    pub name: String,
    pub description: String,
    pub path: Option<String>,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct ProjectModelPreference {
    #[serde(rename = "modelID")]
    pub model_id: Option<String>,
    pub effort: Option<String>,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
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

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ConversationBookmarkKind {
    UserRequest,
    Answer,
    Decision,
    ChangedFile,
    Failure,
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
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppKitDocument {
    version: u64,
    project_path: String,
    context: serde_json::Value,
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
    let content = serde_json::to_string(&context)?;
    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    checkout.revalidate()?;
    let inserted = transaction.execute(
        "INSERT INTO project_contexts (checkout_path, checkout_key, content) VALUES (?1, ?2, ?3)
         ON CONFLICT (checkout_path) DO NOTHING",
        params![path, checkout.storage_key(), content],
    )?;
    transaction.commit()?;
    Ok(if inserted == 1 {
        ProjectContextImport::Imported
    } else {
        ProjectContextImport::PreservedDestination
    })
}

pub fn read_project_context(
    database: &Connection,
    checkout: &CheckoutIdentity,
) -> Result<Option<ProjectContext>, ProjectContextError> {
    checkout.revalidate()?;
    let content: Option<String> = database
        .query_row(
            "SELECT content FROM project_contexts WHERE checkout_path = ?1 AND checkout_key = ?2",
            params![project_path(checkout)?, checkout.storage_key()],
            |row| row.get(0),
        )
        .optional()?;
    content
        .map(|content| serde_json::from_str(&content))
        .transpose()
        .map_err(Into::into)
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

#[cfg(test)]
mod tests;
