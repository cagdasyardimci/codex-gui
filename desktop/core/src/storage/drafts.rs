use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};
use serde_json::Value;
use thiserror::Error;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct DraftId(pub Uuid);

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct DraftRevision(i64);

impl DraftRevision {
    pub const INITIAL: Self = Self(0);

    pub fn next(self) -> Option<Self> {
        self.0.checked_add(1).map(Self)
    }
}

#[derive(Debug, PartialEq)]
pub struct StoredDraft {
    pub revision: DraftRevision,
    pub text: String,
    pub context: Vec<Value>,
}

#[derive(Debug, Default)]
pub struct DraftPatch {
    pub text: Option<String>,
    pub context: Option<Vec<Value>>,
}

#[derive(Debug, Eq, PartialEq)]
pub enum DraftSave {
    Applied,
    Stale { current: Option<DraftRevision> },
}

#[derive(Debug, Error)]
pub enum DraftStoreError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error("could not encode or decode saved draft context: {0}")]
    Context(#[from] serde_json::Error),
}

pub fn read_draft(
    database: &Connection,
    id: DraftId,
) -> Result<Option<StoredDraft>, DraftStoreError> {
    let row = database
        .query_row(
            "SELECT revision, text, context FROM drafts WHERE id = ?1",
            [id.0.as_bytes().as_slice()],
            |row| Ok((row.get::<_, i64>(0)?, row.get(1)?, row.get::<_, String>(2)?)),
        )
        .optional()?;
    row.map(|(revision, text, context)| {
        Ok(StoredDraft {
            revision: DraftRevision(revision),
            text,
            context: serde_json::from_str(&context)?,
        })
    })
    .transpose()
}

pub fn save_draft(
    database: &mut Connection,
    id: DraftId,
    expected: Option<DraftRevision>,
    revision: DraftRevision,
    patch: &DraftPatch,
) -> Result<DraftSave, DraftStoreError> {
    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let id = id.0.as_bytes().as_slice();
    let text = patch.text.as_deref();
    let context = patch
        .context
        .as_ref()
        .map(serde_json::to_string)
        .transpose()?;

    let existing = transaction
        .query_row(
            "SELECT revision,
                CASE WHEN ?2 IS NULL THEN FALSE ELSE text <> ?2 END,
                CASE WHEN ?3 IS NULL THEN FALSE ELSE context <> ?3 END
             FROM drafts WHERE id = ?1",
            params![id, text, context],
            |row| {
                Ok((
                    DraftRevision(row.get(0)?),
                    row.get::<_, bool>(1)?,
                    row.get::<_, bool>(2)?,
                ))
            },
        )
        .optional()?;
    let current = existing.map(|(revision, _, _)| revision);
    if current != expected || current.is_some_and(|saved| saved >= revision) {
        return Ok(DraftSave::Stale { current });
    }
    match existing {
        None => transaction.execute(
            "INSERT INTO drafts (id, revision, text, context)
             VALUES (?1, ?2, COALESCE(?3, ''), COALESCE(?4, '[]'))",
            params![id, revision.0, text, context],
        )?,
        Some((_, true, true)) => transaction.execute(
            "UPDATE drafts SET revision = ?2, text = ?3, context = ?4 WHERE id = ?1",
            params![id, revision.0, text, context],
        )?,
        Some((_, true, false)) => transaction.execute(
            "UPDATE drafts SET revision = ?2, text = ?3 WHERE id = ?1",
            params![id, revision.0, text],
        )?,
        Some((_, false, true)) => transaction.execute(
            "UPDATE drafts SET revision = ?2, context = ?3 WHERE id = ?1",
            params![id, revision.0, context],
        )?,
        Some((_, false, false)) => transaction.execute(
            "UPDATE drafts SET revision = ?2 WHERE id = ?1",
            params![id, revision.0],
        )?,
    };
    transaction.commit()?;
    Ok(DraftSave::Applied)
}

pub(super) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE drafts (
            id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16),
            revision INTEGER NOT NULL CHECK (revision >= 0),
            text TEXT NOT NULL,
            context TEXT NOT NULL CHECK (json_valid(context) AND json_type(context) = 'array')
        ) STRICT, WITHOUT ROWID;",
    )
}

#[cfg(test)]
mod tests;
