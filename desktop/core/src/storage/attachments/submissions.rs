use super::*;
use crate::{checkout::CheckoutIdentity, identity::TurnId};
use uuid::Uuid;

use crate::storage::drafts::retire_submitted_revision;

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
    #[error("the submission received conflicting outcomes")]
    ConflictingOutcome,
}

pub(crate) struct JournalEntry<'a> {
    pub id: RequestId,
    pub thread: &'a ThreadId,
    pub draft: DraftId,
    pub revision: DraftRevision,
    pub request: &'a Value,
    pub attachments: &'a [BlobLease],
    pub checkout: &'a CheckoutIdentity,
}

pub(crate) struct SubmissionWrite {
    store: AttachmentStore,
    id: RequestId,
}

impl Drop for SubmissionWrite {
    fn drop(&mut self) {
        self.store.inner.state().active_submissions.remove(&self.id);
    }
}

pub(crate) struct PendingSubmission {
    pub id: RequestId,
    pub thread: ThreadId,
    pub reserved: bool,
    pub matches_checkout: bool,
}

pub(crate) enum JournalPhase {
    Dispatching,
    Unsent,
}

pub(crate) enum JournalOutcome {
    Accepted(TurnId),
    Rejected { code: i64 },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SubmissionAcknowledgement {
    Accepted { retired_draft: bool },
    Rejected,
    Duplicate,
    Unmatched,
}

impl AttachmentStore {
    pub(crate) fn reserve_submission(
        &self,
        entry: JournalEntry<'_>,
    ) -> Result<SubmissionWrite, JournalError> {
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
            "INSERT INTO submissions (id, thread_id, draft_id, draft_revision, request, phase, checkout_key)
             SELECT ?1, thread_id, draft_id, ?4, ?5, 'reserved', ?6
             FROM thread_drafts WHERE thread_id = ?2 AND draft_id = ?3",
            params![
                id,
                entry.thread.0,
                entry.draft.0.as_bytes().as_slice(),
                entry.revision.as_sql(),
                encoded,
                entry.checkout.storage_key(),
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
        state.active_submissions.insert(entry.id);
        Ok(SubmissionWrite {
            store: self.clone(),
            id: entry.id,
        })
    }

    pub(crate) fn pending_submissions(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<Vec<PendingSubmission>, JournalError> {
        let state = self.inner.state();
        let mut statement = state.database.prepare(
            "SELECT s.id, s.thread_id, s.phase = 'reserved', COALESCE(s.checkout_key = ?2, FALSE)
             FROM submissions AS s
             WHERE json_extract(s.request, '$.cwd') = ?1 AND s.phase IN ('reserved', 'dispatching')
                AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS outcome WHERE outcome.id = s.id)
             ORDER BY s.thread_id, s.id",
        )?;
        let records = statement.query_map(
            params![checkout.canonical_path().to_str(), checkout.storage_key()],
            |row| {
                Ok(PendingSubmission {
                    id: RequestId(Uuid::from_bytes(row.get(0)?)),
                    thread: ThreadId(row.get(1)?),
                    reserved: row.get(2)?,
                    matches_checkout: row.get(3)?,
                })
            },
        )?;
        let mut pending = Vec::new();
        for record in records {
            let record = record?;
            if !state.active_submissions.contains(&record.id) {
                pending.push(record);
            }
        }
        Ok(pending)
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
            if matches!(phase, JournalPhase::Unsent)
                && transaction.query_row(
                    "SELECT EXISTS (SELECT 1 FROM submissions WHERE id = ?1 AND phase = 'unsent')",
                    [id],
                    |row| row.get::<_, bool>(0),
                )?
            {
                return Ok(());
            }
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

    pub(crate) fn acknowledge_submission(
        &self,
        id: RequestId,
        thread: &ThreadId,
        outcome: JournalOutcome,
        checkout: &CheckoutIdentity,
    ) -> Result<SubmissionAcknowledgement, JournalError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = id.0.as_bytes().as_slice();
        let binding = transaction
            .query_row(
                "SELECT draft_id, draft_revision FROM submissions
             WHERE id = ?1 AND thread_id = ?2 AND phase = 'dispatching'
               AND checkout_key = ?3 AND json_extract(request, '$.cwd') = ?4",
                params![
                    id,
                    thread.0,
                    checkout.storage_key(),
                    checkout.canonical_path().to_str()
                ],
                |row| Ok((row.get::<_, [u8; 16]>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional()?;
        let Some((draft_id, revision)) = binding else {
            return Ok(SubmissionAcknowledgement::Unmatched);
        };
        let known = transaction
            .query_row(
                "SELECT turn_id FROM submission_outcomes WHERE id = ?1",
                [id],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()?;
        if let Some(turn) = known {
            return match outcome {
                JournalOutcome::Rejected { .. } => Ok(SubmissionAcknowledgement::Duplicate),
                JournalOutcome::Accepted(incoming)
                    if turn.as_deref() == Some(incoming.0.as_str()) =>
                {
                    Ok(SubmissionAcknowledgement::Duplicate)
                }
                JournalOutcome::Accepted(_) => Err(JournalError::ConflictingOutcome),
            };
        }

        let mut released = Vec::new();
        let acknowledgement = match outcome {
            JournalOutcome::Rejected { code } => {
                transaction.execute(
                    "INSERT INTO submission_outcomes (id, rejection_code) VALUES (?1, ?2)",
                    params![id, code],
                )?;
                SubmissionAcknowledgement::Rejected
            }
            JournalOutcome::Accepted(turn) => {
                transaction.execute(
                    "INSERT INTO submission_outcomes (id, turn_id) VALUES (?1, ?2)",
                    params![id, turn.0],
                )?;
                transaction.execute(
                    "INSERT INTO sent_submission_attachments (submission_id, blob_id)
                     SELECT submission_id, blob_id FROM submission_attachments WHERE submission_id = ?1",
                    [id],
                )?;
                transaction.execute(
                    "DELETE FROM submission_attachments WHERE submission_id = ?1",
                    [id],
                )?;
                let draft = DraftId(Uuid::from_bytes(draft_id));
                let revision = DraftRevision::from_sql(revision);
                let retired_draft = retire_submitted_revision(&transaction, draft, revision)?;
                if retired_draft {
                    released = replace_references(
                        &transaction,
                        &self.inner.blobs,
                        &draft_id,
                        std::iter::empty(),
                    )?;
                }
                SubmissionAcknowledgement::Accepted { retired_draft }
            }
        };
        transaction.commit()?;
        state.candidates.extend(released);
        Ok(acknowledgement)
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

pub(in crate::storage) fn migrate_submission_outcomes(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE submission_outcomes (
            id BLOB NOT NULL PRIMARY KEY REFERENCES submissions (id) ON DELETE CASCADE,
            turn_id TEXT CHECK (length(turn_id) > 0),
            rejection_code INTEGER,
            CHECK ((turn_id IS NULL) <> (rejection_code IS NULL))
        ) STRICT, WITHOUT ROWID;
        CREATE TABLE sent_submission_attachments (
            submission_id BLOB NOT NULL REFERENCES submission_outcomes (id) ON DELETE CASCADE,
            blob_id BLOB NOT NULL REFERENCES attachment_blobs (id) ON DELETE RESTRICT,
            PRIMARY KEY (submission_id, blob_id)
        ) STRICT, WITHOUT ROWID;
        CREATE INDEX sent_submission_attachments_blob ON sent_submission_attachments (blob_id);",
    )
}

pub(in crate::storage) fn migrate_submission_checkout(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch("ALTER TABLE submissions ADD COLUMN checkout_key TEXT")
}
