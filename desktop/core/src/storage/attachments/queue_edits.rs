use super::*;
use crate::{
    checkout::CheckoutIdentity,
    codex::QueuedSubmission,
    storage::drafts::{DraftSave, StoredDraft, retire_submitted_revision},
};
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum QueueEditError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Attachment(#[from] AttachmentError),
    #[error(transparent)]
    Draft(#[from] DraftStoreError),
    #[error("the composer already owns a draft or queue edit")]
    OccupiedDraft,
    #[error("the queue edit has changed or finished")]
    Changed,
    #[error("the captured queue input is invalid")]
    InvalidInput,
}

#[derive(Clone, Debug)]
pub struct QueueEdit {
    pub id: Uuid,
    pub draft: DraftId,
    pub thread: ThreadId,
    pub entry: QueuedSubmission,
}

impl AttachmentStore {
    pub fn queue_edit(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<Option<QueueEdit>, QueueEditError> {
        let state = self.inner.state();
        read_queue_edit(&state.database, checkout, thread)
    }

    pub(crate) fn begin_queue_edit(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        entry: QueuedSubmission,
    ) -> Result<QueueEdit, QueueEditError> {
        let draft_id = self.editable_thread_draft(thread)?;
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let draft = read_draft(&tx, draft_id)?.ok_or(AttachmentError::MissingDraft)?;
        let id = draft_id.0.as_bytes().as_slice();
        if !draft.text.is_empty()
            || !draft.context.is_empty()
            || read_queue_edit(&tx, checkout, thread)?.is_some()
            || tx.query_row(
                "SELECT EXISTS (SELECT 1 FROM draft_attachments WHERE draft_id = ?1)",
                [id],
                |row| row.get::<_, bool>(0),
            )?
        {
            return Err(QueueEditError::OccupiedDraft);
        }
        let (text, context) =
            split_queue_input(&entry.input).ok_or(QueueEditError::InvalidInput)?;
        let revision = draft.revision.next().ok_or(QueueEditError::Changed)?;
        let saved = save_in_transaction(
            &tx,
            draft_id,
            Some(draft.revision),
            revision,
            Some(text),
            Some(context),
        )?;
        if saved != DraftSave::Applied {
            return Err(QueueEditError::Changed);
        }
        if let Ok(request) = Uuid::parse_str(&entry.client_user_message_id) {
            // Keep the composer’s references distinct from the server queue’s owner.
            tx.execute(
                "INSERT INTO draft_attachments (draft_id, blob_id)
                 SELECT ?1, a.blob_id FROM submission_attachments AS a
                 JOIN submissions AS s ON s.id = a.submission_id
                 LEFT JOIN queue_receipts AS q ON q.id = s.id
                 LEFT JOIN legacy_queue AS l ON l.id = s.id
                 WHERE s.id = ?2 AND s.checkout_key = ?3 AND s.thread_id = ?4
                    AND ((q.queued_id = ?5 AND NOT q.deleted)
                         OR (l.id IS NOT NULL AND s.phase = 'reserved' AND ?5 = ?6))",
                params![
                    id,
                    request.as_bytes().as_slice(),
                    checkout.storage_key(),
                    thread.0,
                    entry.id,
                    entry.client_user_message_id
                ],
            )?;
        }
        let edit = QueueEdit {
            id: Uuid::new_v4(),
            draft: draft_id,
            thread: thread.clone(),
            entry,
        };
        tx.execute(
            "INSERT INTO queue_edits (checkout_key, thread_id, id, draft_id, client_id, entry)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                checkout.storage_key(),
                thread.0,
                edit.id.as_bytes().as_slice(),
                id,
                edit.entry.client_user_message_id,
                serde_json::to_string(&edit.entry)?,
            ],
        )?;
        tx.commit()?;
        Ok(edit)
    }

    pub(crate) fn capture_queue_edit(
        &self,
        checkout: &CheckoutIdentity,
        edit: &QueueEdit,
    ) -> Result<StoredDraft, QueueEditError> {
        let state = self.inner.state();
        let saved = read_queue_edit(&state.database, checkout, &edit.thread)?
            .ok_or(QueueEditError::Changed)?;
        if saved.id != edit.id || saved.entry != edit.entry {
            return Err(QueueEditError::Changed);
        }
        Ok(read_draft(&state.database, saved.draft)?.ok_or(AttachmentError::MissingDraft)?)
    }

    pub(crate) fn finish_queue_edit(
        &self,
        checkout: &CheckoutIdentity,
        edit: &QueueEdit,
        outcome: QueueEditOutcome,
    ) -> Result<(), QueueEditError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let Some(saved) = read_queue_edit(&tx, checkout, &edit.thread)?
            .filter(|saved| saved.id == edit.id && saved.entry == edit.entry)
        else {
            return Ok(());
        };
        let key = saved.id.as_bytes().as_slice();
        let mut release = Vec::new();
        let revision = match outcome {
            QueueEditOutcome::Detach => None,
            QueueEditOutcome::Discard => {
                let draft = read_draft(&tx, saved.draft)?.ok_or(AttachmentError::MissingDraft)?;
                Some(draft.revision)
            }
            QueueEditOutcome::Updated {
                entry,
                revision,
                legacy,
            } => {
                if legacy {
                    let id = Uuid::parse_str(&entry.client_user_message_id)
                        .map_err(|_| QueueEditError::Changed)?;
                    let updated = tx.execute(
                        "UPDATE submissions SET request = json_replace(request, '$.input', json(?4))
                         WHERE id = ?1 AND checkout_key = ?2 AND thread_id = ?3 AND phase = 'reserved'
                           AND EXISTS (SELECT 1 FROM legacy_queue AS l WHERE l.id = ?1)",
                        params![id.as_bytes().as_slice(), checkout.storage_key(), edit.thread.0,
                                serde_json::to_string(&entry.input)?],
                    )?;
                    if updated != 1 {
                        return Err(QueueEditError::Changed);
                    }
                }
                let draft = read_draft(&tx, saved.draft)?.ok_or(AttachmentError::MissingDraft)?;
                if draft.revision != revision {
                    tx.execute(
                        "UPDATE queue_edits SET entry = ?2 WHERE id = ?1",
                        params![key, serde_json::to_string(&entry)?],
                    )?;
                    tx.commit()?;
                    return Ok(());
                }
                Some(revision)
            }
        };
        if let Some(revision) = revision {
            retire_submitted_revision(&tx, saved.draft, revision)?;
            release = replace_references(
                &tx,
                &self.inner.blobs,
                saved.draft.0.as_bytes().as_slice(),
                std::iter::empty(),
            )?;
        }
        tx.execute("DELETE FROM queue_edits WHERE id = ?1", [key])?;
        tx.commit()?;
        state.candidates.extend(release);
        Ok(())
    }

    pub(crate) fn detach_consumed_queue_edit(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        client_id: &str,
    ) -> Result<(), QueueEditError> {
        let state = self.inner.state();
        state.database.execute(
            "DELETE FROM queue_edits WHERE checkout_key = ?1 AND thread_id = ?2 AND client_id = ?3",
            params![checkout.storage_key(), thread.0, client_id],
        )?;
        Ok(())
    }
}

pub(crate) enum QueueEditOutcome {
    Detach,
    Discard,
    Updated {
        entry: QueuedSubmission,
        revision: DraftRevision,
        legacy: bool,
    },
}

pub(super) fn split_queue_input(input: &[Value]) -> Option<(&str, &[Value])> {
    let (first, rest) = input.split_first()?;
    if first["type"] == "text" {
        Some((first["text"].as_str()?, rest))
    } else {
        Some(("", input))
    }
}

fn read_queue_edit(
    database: &Connection,
    checkout: &CheckoutIdentity,
    thread: &ThreadId,
) -> Result<Option<QueueEdit>, QueueEditError> {
    let entry = database.query_row(
        "SELECT id, draft_id, entry FROM queue_edits WHERE checkout_key = ?1 AND thread_id = ?2",
        params![checkout.storage_key(), thread.0],
        |row| Ok((row.get::<_, [u8; 16]>(0)?, row.get::<_, [u8; 16]>(1)?, row.get::<_, String>(2)?)),
    ).optional()?;
    entry
        .map(|(id, draft, entry)| {
            Ok(QueueEdit {
                id: Uuid::from_bytes(id),
                draft: DraftId(Uuid::from_bytes(draft)),
                thread: thread.clone(),
                entry: serde_json::from_str(&entry)?,
            })
        })
        .transpose()
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE queue_edits (
           checkout_key TEXT NOT NULL,
           thread_id TEXT NOT NULL,
           id BLOB NOT NULL UNIQUE CHECK (length(id) = 16),
           draft_id BLOB NOT NULL UNIQUE REFERENCES drafts (id) ON DELETE RESTRICT,
           client_id TEXT NOT NULL CHECK (length(client_id) > 0),
           entry TEXT NOT NULL CHECK (json_valid(entry) AND json_type(entry) = 'object'),
           PRIMARY KEY (checkout_key, thread_id)
         ) STRICT, WITHOUT ROWID;",
    )
}
