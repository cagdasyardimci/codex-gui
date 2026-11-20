use std::{path::Path, time::Duration};

use rusqlite::{Connection, Transaction, TransactionBehavior};
use thiserror::Error;

pub mod attachments;
pub mod drafts;
pub mod project_context;
pub mod writes;

const APPLICATION_ID: i32 = i32::from_be_bytes(*b"CGUI");
const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

type Migration = fn(&Transaction<'_>) -> rusqlite::Result<()>;
const MIGRATIONS: &[Migration] = &[
    |transaction| transaction.pragma_update(None, "application_id", APPLICATION_ID),
    drafts::migrate,
    attachments::migrate,
    attachments::migrate_thread_drafts,
    attachments::migrate_submissions,
    attachments::migrate_submission_outcomes,
    attachments::migrate_submission_checkout,
    project_context::migrate,
    attachments::appkit_drafts::migrate,
    attachments::navigation::migrate,
    attachments::exit_recovery::migrate,
    attachments::migrate_queue_receipts,
    attachments::queue_edits::migrate,
    attachments::migrate_queue_deletions,
    attachments::legacy_queue::migrate,
    attachments::queue_steering::migrate,
    attachments::queue_preferences::migrate,
    attachments::appkit_drafts::queues::migrate,
    attachments::exit_recovery::migrate_checkout_paths,
    attachments::composer_settings::migrate,
    project_context::migrate_revisions,
    attachments::composer_plan::migrate,
    attachments::fork_revisions::migrate,
    attachments::fork_revisions::migrate_fork_receipts,
    attachments::sidebar::migrate,
    attachments::sidebar::migrate_archive,
    attachments::chat_deletion::migrate,
];

#[derive(Debug, Error)]
pub enum DatabaseOpenError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error("the file belongs to another SQLite application")]
    ForeignDatabase,
    #[error("unsupported workspace schema version {0}")]
    UnsupportedSchema(i32),
}

pub fn open_workspace_database(path: &Path) -> Result<Connection, DatabaseOpenError> {
    let mut database = Connection::open(path)?;
    database.busy_timeout(BUSY_TIMEOUT)?;
    database.pragma_update(None, "foreign_keys", true)?;

    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let application: i32 =
        transaction.pragma_query_value(None, "application_id", |row| row.get(0))?;
    let version: i32 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    validate_identity(&transaction, application, version)?;

    let first =
        usize::try_from(version).map_err(|_| DatabaseOpenError::UnsupportedSchema(version))?;
    let remaining = MIGRATIONS
        .get(first..)
        .ok_or(DatabaseOpenError::UnsupportedSchema(version))?;
    for migrate in remaining {
        migrate(&transaction)?;
    }
    if !remaining.is_empty() {
        let current = i32::try_from(MIGRATIONS.len()).expect("schema version fits SQLite metadata");
        transaction.pragma_update(None, "user_version", current)?;
    }
    transaction.commit()?;
    Ok(database)
}

fn validate_identity(
    transaction: &Transaction<'_>,
    application: i32,
    version: i32,
) -> Result<(), DatabaseOpenError> {
    if application == APPLICATION_ID {
        return Ok(());
    }
    if application == 0 && version == 0 {
        let has_schema: bool =
            transaction.query_row("SELECT EXISTS (SELECT 1 FROM sqlite_schema)", [], |row| {
                row.get(0)
            })?;
        if !has_schema {
            return Ok(());
        }
    }
    Err(DatabaseOpenError::ForeignDatabase)
}

#[cfg(test)]
mod tests;
