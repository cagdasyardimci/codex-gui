use super::*;
use crate::codex::QueuedSubmission;
use crate::{
    checkout::CheckoutIdentity,
    identity::{ConnectionIdentity, TurnId},
};
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
    #[error("the draft revision was already accepted or a submission still awaits reconciliation")]
    PendingDraft,
}

pub(crate) struct JournalEntry<'a> {
    pub id: RequestId,
    pub thread: &'a ThreadId,
    pub draft: DraftId,
    pub revision: DraftRevision,
    pub request: &'a Value,
    pub attachments: &'a [BlobLease],
    pub checkout: &'a CheckoutIdentity,
    pub kind: JournalKind<'a>,
}

#[derive(Clone, Copy)]
pub(crate) enum JournalKind<'a> {
    Direct,
    ServerQueue,
    LegacyQueue(&'a ConnectionIdentity),
}

pub(crate) struct SubmissionWrite {
    pub(super) store: AttachmentStore,
    pub(super) id: RequestId,
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
    pub queue_add: bool,
    pub queued_id: Option<String>,
}

pub(crate) enum JournalPhase {
    Dispatching,
    Unsent,
}

pub(crate) enum JournalOutcome {
    Accepted(TurnId),
    Rejected { code: i64 },
    Queued(String),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SubmissionAcknowledgement {
    Accepted { retired_draft: bool },
    Rejected,
    Queued { retired_draft: bool },
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
        if transaction.query_row(
            "SELECT EXISTS (SELECT 1 FROM queue_edits WHERE draft_id = ?1 AND checkout_key = ?2)",
            params![
                entry.draft.0.as_bytes().as_slice(),
                entry.checkout.storage_key()
            ],
            |row| row.get::<_, bool>(0),
        )? {
            return Err(JournalError::PendingDraft);
        }
        if !matches!(entry.kind, JournalKind::Direct)
            && transaction.query_row(
                "SELECT EXISTS (
                     SELECT 1 FROM submissions AS s
                     LEFT JOIN queue_receipts AS q ON q.id = s.id
                     LEFT JOIN legacy_queue AS l ON l.id = s.id
                     LEFT JOIN submission_outcomes AS o ON o.id = s.id
                     WHERE s.draft_id = ?1 AND s.checkout_key = ?2
                       AND s.phase IN ('reserved', 'dispatching')
                       AND ((o.id IS NULL AND q.queued_id IS NULL AND (l.id IS NULL OR s.phase = 'dispatching'))
                            OR (s.draft_revision = ?3 AND (q.queued_id IS NOT NULL OR l.id IS NOT NULL OR o.turn_id IS NOT NULL)))
                 )",
                params![
                    entry.draft.0.as_bytes().as_slice(),
                    entry.checkout.storage_key(),
                    entry.revision.as_sql()
                ],
                |row| row.get::<_, bool>(0),
            )?
        {
            return Err(JournalError::PendingDraft);
        }
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
        if matches!(entry.kind, JournalKind::ServerQueue) {
            transaction.execute("INSERT INTO queue_receipts (id) VALUES (?1)", [id])?;
        }
        let unique: BTreeSet<_> = entry.attachments.iter().map(BlobLease::id).collect();
        for blob in unique {
            verify_saved_file(&transaction, &self.inner.blobs, blob)?;
            transaction.execute(
                "INSERT INTO submission_attachments (submission_id, blob_id) VALUES (?1, ?2)",
                params![id, blob.0.as_slice()],
            )?;
        }
        let mut released = Vec::new();
        if let JournalKind::LegacyQueue(owner) = entry.kind {
            super::legacy_queue::insert_legacy_entry(&transaction, &entry, owner)?;
            if retire_submitted_revision(&transaction, entry.draft, entry.revision)? {
                released = replace_references(
                    &transaction,
                    &self.inner.blobs,
                    entry.draft.0.as_bytes().as_slice(),
                    std::iter::empty(),
                )?;
            }
        }
        transaction.commit()?;
        state.candidates.extend(released);
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
        self.read_pending_submissions(checkout, None)
    }

    pub(crate) fn pending_queue_submissions(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<Vec<PendingSubmission>, JournalError> {
        self.read_pending_submissions(checkout, Some(thread))
    }

    pub fn queue_receipts_need_recovery(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        listed: &[QueuedSubmission],
    ) -> Result<bool, JournalError> {
        Ok(self
            .pending_queue_submissions(checkout, thread)?
            .iter()
            .any(|pending| {
                !listed.iter().any(|entry| {
                    Some(entry.id.as_str()) == pending.queued_id.as_deref()
                        && Uuid::parse_str(&entry.client_user_message_id).ok() == Some(pending.id.0)
                })
            }))
    }

    fn read_pending_submissions(
        &self,
        checkout: &CheckoutIdentity,
        queue_thread: Option<&ThreadId>,
    ) -> Result<Vec<PendingSubmission>, JournalError> {
        let state = self.inner.state();
        let mut statement = state.database.prepare(
            "SELECT s.id, s.thread_id, s.phase = 'reserved', COALESCE(s.checkout_key = ?2, FALSE),
                    q.id IS NOT NULL, q.queued_id
             FROM submissions AS s
             LEFT JOIN queue_receipts AS q ON q.id = s.id
             LEFT JOIN legacy_queue AS l ON l.id = s.id
             WHERE json_extract(s.request, '$.cwd') = ?1 AND s.phase IN ('reserved', 'dispatching')
                AND NOT COALESCE(q.deleted, FALSE)
                AND (l.id IS NULL OR s.phase = 'dispatching')
                AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS outcome WHERE outcome.id = s.id)
                AND (?3 IS NULL OR (
                     s.thread_id = ?3 AND s.checkout_key = ?2 AND (q.id IS NOT NULL OR l.id IS NOT NULL)
                     AND NOT EXISTS (
                         SELECT 1 FROM queue_steering AS st WHERE st.checkout_key = s.checkout_key
                           AND st.thread_id = s.thread_id AND lower(replace(st.client_id, '-', '')) = lower(hex(s.id))
                     )
                ))
             ORDER BY s.thread_id, s.id",
        )?;
        let records = statement.query_map(
            params![
                checkout.canonical_path().to_str(),
                checkout.storage_key(),
                queue_thread.map(|thread| &thread.0)
            ],
            |row| {
                Ok(PendingSubmission {
                    id: RequestId(Uuid::from_bytes(row.get(0)?)),
                    thread: ThreadId(row.get(1)?),
                    reserved: row.get(2)?,
                    matches_checkout: row.get(3)?,
                    queue_add: row.get(4)?,
                    queued_id: row.get(5)?,
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

    pub fn has_unresolved_submission(
        &self,
        checkout: &CheckoutIdentity,
        draft: DraftId,
    ) -> Result<bool, JournalError> {
        let state = self.inner.state();
        let mut query = state.database.prepare(
            "SELECT s.id FROM submissions AS s
             LEFT JOIN queue_receipts AS q ON q.id = s.id
             LEFT JOIN legacy_queue AS l ON l.id = s.id
             WHERE s.checkout_key = ?1 AND s.draft_id = ?2
               AND s.phase IN ('reserved', 'dispatching') AND q.queued_id IS NULL
               AND (l.id IS NULL OR s.phase = 'dispatching')
               AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = s.id)",
        )?;
        let ids = query.query_map(
            params![checkout.storage_key(), draft.0.as_bytes().as_slice()],
            |row| row.get(0).map(|id| RequestId(Uuid::from_bytes(id))),
        )?;
        for id in ids {
            if !state.active_submissions.contains(&id?) {
                return Ok(true);
            }
        }
        Ok(false)
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
        let released = if matches!(phase, JournalPhase::Unsent) {
            release_submission_attachments(&transaction, id)?
        } else {
            Vec::new()
        };
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
                "SELECT s.draft_id, s.draft_revision, q.id IS NOT NULL, q.queued_id, l.id IS NOT NULL,
                    json_extract(s.request, '$.expectedTurnId')
                 FROM submissions AS s LEFT JOIN queue_receipts AS q ON q.id = s.id
                 LEFT JOIN legacy_queue AS l ON l.id = s.id
                 WHERE s.id = ?1 AND s.thread_id = ?2 AND s.phase = 'dispatching'
                   AND s.checkout_key = ?3 AND json_extract(s.request, '$.cwd') = ?4
                   AND NOT COALESCE(q.deleted, FALSE)",
                params![
                    id,
                    thread.0,
                    checkout.storage_key(),
                    checkout.canonical_path().to_str()
                ],
                |row| {
                    Ok((
                        row.get::<_, [u8; 16]>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, bool>(2)?,
                        row.get::<_, Option<String>>(3)?,
                        row.get::<_, bool>(4)?,
                        row.get::<_, Option<String>>(5)?,
                    ))
                },
            )
            .optional()?;
        let Some((draft_id, revision, queue_add, queued_id, legacy, expected_turn)) = binding
        else {
            return Ok(SubmissionAcknowledgement::Unmatched);
        };
        if matches!(&outcome, JournalOutcome::Queued(_)) && !queue_add {
            return Ok(SubmissionAcknowledgement::Unmatched);
        }
        if let (Some(expected), JournalOutcome::Accepted(turn)) = (&expected_turn, &outcome)
            && expected != &turn.0
        {
            return Ok(SubmissionAcknowledgement::Unmatched);
        }
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
                JournalOutcome::Queued(incoming)
                    if turn.is_some() && queued_id.as_ref().is_none_or(|id| id == &incoming) =>
                {
                    Ok(SubmissionAcknowledgement::Duplicate)
                }
                _ => Err(JournalError::ConflictingOutcome),
            };
        }

        let mut released = Vec::new();
        let acknowledgement = match outcome {
            JournalOutcome::Rejected { code } => {
                if queued_id.is_some() {
                    return Err(JournalError::ConflictingOutcome);
                }
                transaction.execute(
                    "INSERT INTO submission_outcomes (id, rejection_code) VALUES (?1, ?2)",
                    params![id, code],
                )?;
                if queue_add {
                    released = release_submission_attachments(&transaction, id)?;
                }
                SubmissionAcknowledgement::Rejected
            }
            JournalOutcome::Queued(incoming) => {
                if let Some(known) = queued_id {
                    return if known == incoming {
                        Ok(SubmissionAcknowledgement::Duplicate)
                    } else {
                        Err(JournalError::ConflictingOutcome)
                    };
                }
                transaction.execute(
                    "UPDATE queue_receipts SET queued_id = ?2 WHERE id = ?1",
                    params![id, incoming],
                )?;
                SubmissionAcknowledgement::Queued {
                    retired_draft: retire_submitted_revision(
                        &transaction,
                        DraftId(Uuid::from_bytes(draft_id)),
                        DraftRevision::from_sql(revision),
                    )?,
                }
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
                let retired_draft = queued_id.is_none()
                    && !legacy
                    && retire_submitted_revision(
                        &transaction,
                        DraftId(Uuid::from_bytes(draft_id)),
                        DraftRevision::from_sql(revision),
                    )?;
                SubmissionAcknowledgement::Accepted { retired_draft }
            }
        };
        if matches!(
            acknowledgement,
            SubmissionAcknowledgement::Accepted {
                retired_draft: true
            } | SubmissionAcknowledgement::Queued {
                retired_draft: true
            }
        ) {
            released.extend(replace_references(
                &transaction,
                &self.inner.blobs,
                &draft_id,
                std::iter::empty(),
            )?);
        }
        transaction.commit()?;
        state.candidates.extend(released);
        Ok(acknowledgement)
    }

    pub(crate) fn record_queue_deletion(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        entry: &QueuedSubmission,
    ) -> Result<(), JournalError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let scope = checkout.storage_key();
        let mut released = Vec::new();
        if let Ok(client) = Uuid::parse_str(&entry.client_user_message_id) {
            let request_id = client.as_bytes().as_slice();
            let binding = transaction
                .query_row(
                    "SELECT s.draft_id, s.draft_revision, q.queued_id IS NULL
                 FROM submissions AS s JOIN queue_receipts AS q ON s.id = q.id
                 WHERE s.id = ?1 AND (q.queued_id = ?2 OR q.queued_id IS NULL) AND NOT q.deleted
                   AND s.thread_id = ?3 AND s.checkout_key = ?4 AND s.phase = 'dispatching'
                   AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = s.id)",
                    params![request_id, entry.id, thread.0, scope],
                    |row| {
                        Ok((
                            row.get::<_, [u8; 16]>(0)?,
                            row.get::<_, i64>(1)?,
                            row.get::<_, bool>(2)?,
                        ))
                    },
                )
                .optional()?;
            if let Some((draft, revision, add_was_unconfirmed)) = binding {
                transaction.execute(
                    "UPDATE queue_receipts SET queued_id = ?2, deleted = TRUE WHERE id = ?1",
                    params![request_id, entry.id],
                )?;
                released = release_submission_attachments(&transaction, request_id)?;
                if add_was_unconfirmed
                    && retire_submitted_revision(
                        &transaction,
                        DraftId(Uuid::from_bytes(draft)),
                        DraftRevision::from_sql(revision),
                    )?
                {
                    released.extend(replace_references(
                        &transaction,
                        &self.inner.blobs,
                        &draft,
                        std::iter::empty(),
                    )?);
                }
            }
        }
        transaction.execute(
            "DELETE FROM queue_edits WHERE checkout_key = ?1 AND thread_id = ?2 AND client_id = ?3
               AND json_extract(entry, '$.id') = ?4",
            params![scope, thread.0, entry.client_user_message_id, entry.id],
        )?;
        transaction.commit()?;
        state.candidates.extend(released);
        Ok(())
    }
}

pub(super) fn release_submission_attachments(
    transaction: &Transaction<'_>,
    id: &[u8],
) -> rusqlite::Result<Vec<BlobId>> {
    let mut delete = transaction
        .prepare("DELETE FROM submission_attachments WHERE submission_id = ?1 RETURNING blob_id")?;
    delete
        .query_map([id], |row| row.get::<_, [u8; 32]>(0).map(BlobId))?
        .collect()
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

pub(in crate::storage) fn migrate_queue_receipts(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE INDEX submissions_checkout_draft ON submissions (checkout_key, draft_id);
        CREATE TABLE queue_receipts (
            id BLOB NOT NULL PRIMARY KEY REFERENCES submissions (id) ON DELETE CASCADE,
            queued_id TEXT CHECK (length(queued_id) > 0)
        ) STRICT, WITHOUT ROWID;",
    )
}

pub(in crate::storage) fn migrate_queue_deletions(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "ALTER TABLE queue_receipts ADD COLUMN deleted INTEGER NOT NULL DEFAULT FALSE
          CHECK (deleted IN (FALSE, TRUE) AND (NOT deleted OR queued_id IS NOT NULL))",
    )
}
