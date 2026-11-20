use super::*;
use crate::identity::RequestId;

#[derive(Debug, Error)]
pub enum JournalError {
    #[error(transparent)]
    Database(#[from] rusqlite::Error),
    #[error(transparent)]
    Payload(#[from] serde_json::Error),
    #[error(transparent)]
    Attachment(#[from] AttachmentError),
    #[error("the submission no longer has the expected journal state")]
    InvalidPhase,
}

pub(crate) struct JournalEntry<'a> {
    pub id: RequestId,
    pub thread: &'a ThreadId,
    pub draft: DraftId,
    pub revision: DraftRevision,
    pub request: &'a Value,
    pub attachments: &'a [BlobLease],
}

pub(crate) enum JournalPhase {
    Dispatching,
    Unsent,
}

impl AttachmentStore {
    pub(crate) fn reserve_submission(&self, entry: JournalEntry<'_>) -> Result<(), JournalError> {
        if entry
            .attachments
            .iter()
            .any(|lease| !Arc::ptr_eq(&self.inner, &lease.store))
        {
            return Err(AttachmentError::ForeignLease.into());
        }
        let encoded = serde_json::to_string(entry.request)?;
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = entry.id.0.as_bytes().as_slice();
        let inserted = transaction.execute(
            "INSERT INTO submissions (id, thread_id, draft_id, draft_revision, request, phase)
             SELECT ?1, thread_id, draft_id, ?4, ?5, 'reserved'
             FROM thread_drafts WHERE thread_id = ?2 AND draft_id = ?3",
            params![
                id,
                entry.thread.0,
                entry.draft.0.as_bytes().as_slice(),
                entry.revision.as_sql(),
                encoded
            ],
        )?;
        if inserted == 0 {
            return Err(AttachmentError::ConflictingThreadDraft.into());
        }
        let unique: BTreeSet<_> = entry.attachments.iter().map(BlobLease::id).collect();
        for blob in unique {
            verify_saved_file(&transaction, &self.inner.blobs, blob)?;
            transaction.execute(
                "INSERT INTO submission_attachments (submission_id, blob_id) VALUES (?1, ?2)",
                params![id, blob.0.as_slice()],
            )?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub(crate) fn set_submission_phase(
        &self,
        id: RequestId,
        phase: JournalPhase,
    ) -> Result<(), JournalError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = id.0.as_bytes().as_slice();
        let updated = match phase {
            JournalPhase::Dispatching => transaction.execute(
                "UPDATE submissions SET phase = 'dispatching' WHERE id = ?1 AND phase = 'reserved'",
                [id],
            )?,
            JournalPhase::Unsent => transaction.execute(
                "UPDATE submissions SET phase = 'unsent' WHERE id = ?1 AND phase IN ('reserved', 'dispatching')",
                [id],
            )?,
        };
        if updated != 1 {
            return Err(JournalError::InvalidPhase);
        }
        let mut released = Vec::new();
        if matches!(phase, JournalPhase::Unsent) {
            let mut delete = transaction.prepare(
                "DELETE FROM submission_attachments WHERE submission_id = ?1 RETURNING blob_id",
            )?;
            released = delete
                .query_map([id], |row| row.get::<_, [u8; 32]>(0).map(BlobId))?
                .collect::<Result<Vec<_>, _>>()?;
        }
        transaction.commit()?;
        state.candidates.extend(released);
        Ok(())
    }
}

pub(in crate::storage) fn migrate_submissions(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE submissions (
            id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16),
            thread_id TEXT NOT NULL CHECK (length(thread_id) > 0),
            draft_id BLOB NOT NULL CHECK (length(draft_id) = 16),
            draft_revision INTEGER NOT NULL CHECK (draft_revision >= 0),
            request TEXT NOT NULL CHECK (json_valid(request) AND json_type(request) = 'object'),
            phase TEXT NOT NULL CHECK (phase IN ('reserved', 'dispatching', 'unsent'))
        ) STRICT, WITHOUT ROWID;
        CREATE TABLE submission_attachments (
            submission_id BLOB NOT NULL REFERENCES submissions (id) ON DELETE CASCADE,
            blob_id BLOB NOT NULL REFERENCES attachment_blobs (id) ON DELETE RESTRICT,
            PRIMARY KEY (submission_id, blob_id)
        ) STRICT, WITHOUT ROWID;
        CREATE INDEX submission_attachments_blob ON submission_attachments (blob_id);",
    )
}
