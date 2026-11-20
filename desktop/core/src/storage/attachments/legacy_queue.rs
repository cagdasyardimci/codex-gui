use super::*;
use crate::{checkout::CheckoutIdentity, identity::ConnectionIdentity};
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LegacyQueueStatus {
    Ready,
    Paused,
    AwaitingEvidence,
}

#[derive(Debug)]
pub struct LegacyQueueEntry {
    pub id: RequestId,
    pub input: Vec<Value>,
    pub status: LegacyQueueStatus,
}

pub(crate) struct LegacyDispatch {
    pub id: RequestId,
    pub request: Value,
    _write: SubmissionWrite,
}

struct LegacyRecord {
    id: RequestId,
    request: String,
    status: LegacyQueueStatus,
}

const LEGACY_RECORDS: &str = "SELECT s.id, s.request, s.phase = 'dispatching',
            l.paused OR l.session_id <> ?3 OR l.generation <> ?4
     FROM legacy_queue AS l JOIN submissions AS s ON s.id = l.id
     WHERE s.checkout_key = ?1 AND s.thread_id = ?2 AND s.phase IN ('reserved', 'dispatching')
       AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = s.id)
     ORDER BY COALESCE(l.sort_key, l.position)";

fn record(row: &rusqlite::Row<'_>) -> rusqlite::Result<LegacyRecord> {
    let status = if row.get::<_, bool>(2)? {
        LegacyQueueStatus::AwaitingEvidence
    } else if row.get::<_, bool>(3)? {
        LegacyQueueStatus::Paused
    } else {
        LegacyQueueStatus::Ready
    };
    Ok(LegacyRecord {
        id: RequestId(Uuid::from_bytes(row.get(0)?)),
        request: row.get(1)?,
        status,
    })
}

impl AttachmentStore {
    pub(crate) fn delete_local_follow_up(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        id: RequestId,
    ) -> Result<(), JournalError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let scope = checkout.storage_key();
        let key = id.0.as_bytes().as_slice();
        let owned = tx.query_row(
            "SELECT EXISTS (
                 SELECT 1 FROM submissions AS s JOIN legacy_queue AS l ON l.id = s.id
                 WHERE s.id = ?1 AND s.checkout_key = ?2 AND s.thread_id = ?3 AND s.phase = 'reserved'
             )",
            params![key, scope, thread.0], |row| row.get::<_, bool>(0),
        )?;
        if !owned {
            return Err(JournalError::InvalidPhase);
        }
        let released = super::submissions::release_submission_attachments(&tx, key)?;
        tx.execute("DELETE FROM submissions WHERE id = ?1", [key])?;
        tx.execute(
            "DELETE FROM queue_edits WHERE checkout_key = ?1 AND thread_id = ?2 AND client_id = ?3",
            params![scope, thread.0, id.0.to_string()],
        )?;
        tx.commit()?;
        state.candidates.extend(released);
        Ok(())
    }

    pub(crate) fn reorder_local_follow_ups(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        order: &[RequestId],
    ) -> Result<(), JournalError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let current = {
            let mut query = tx.prepare(
                "SELECT s.id, COALESCE(l.sort_key, l.position), s.phase = 'reserved'
                 FROM submissions AS s JOIN legacy_queue AS l ON l.id = s.id
                 WHERE s.checkout_key = ?1 AND s.thread_id = ?2 AND s.phase IN ('reserved', 'dispatching')
                   AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = s.id)
                 ORDER BY COALESCE(l.sort_key, l.position)",
            )?;
            query
                .query_map(params![checkout.storage_key(), thread.0], |row| {
                    Ok((
                        RequestId(Uuid::from_bytes(row.get(0)?)),
                        row.get::<_, i64>(1)?,
                        row.get::<_, bool>(2)?,
                    ))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        if order.len() != current.len()
            || current.iter().any(|row| !row.2)
            || order.iter().copied().collect::<HashSet<_>>()
                != current.iter().map(|row| row.0).collect()
        {
            return Err(JournalError::InvalidPhase);
        }
        for (id, (_, position, _)) in order.iter().zip(current) {
            tx.execute(
                "UPDATE legacy_queue SET sort_key = ?2 WHERE id = ?1",
                params![id.0.as_bytes().as_slice(), position],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn legacy_queue(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        owner: &ConnectionIdentity,
    ) -> Result<Vec<LegacyQueueEntry>, JournalError> {
        let state = self.inner.state();
        let mut query = state.database.prepare(LEGACY_RECORDS)?;
        let entries = query.query_map(
            params![
                checkout.storage_key(),
                thread.0,
                owner.workspace.session.0.as_bytes().as_slice(),
                owner.generation.0.to_le_bytes().as_slice()
            ],
            record,
        )?;
        entries
            .map(|row| {
                let row = row?;
                let mut request: Value = serde_json::from_str(&row.request)?;
                Ok(LegacyQueueEntry {
                    id: row.id,
                    input: serde_json::from_value(request["input"].take())?,
                    status: row.status,
                })
            })
            .collect()
    }

    pub(crate) fn claim_legacy_dispatch(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        owner: &ConnectionIdentity,
        resume: Option<RequestId>,
    ) -> Result<Option<LegacyDispatch>, JournalError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let key = checkout.storage_key();
        let session = owner.workspace.session.0.as_bytes().as_slice();
        let generation = owner.generation.0.to_le_bytes();
        let next = tx
            .query_row(
                &format!("{LEGACY_RECORDS} LIMIT 1"),
                params![key, thread.0, session, generation.as_slice()],
                record,
            )
            .optional()?;
        let Some(next) = next.filter(|next| match resume {
            Some(id) => id == next.id && next.status != LegacyQueueStatus::AwaitingEvidence,
            None => next.status == LegacyQueueStatus::Ready,
        }) else {
            return Ok(None);
        };
        let request = serde_json::from_str(&next.request)?;
        tx.execute(
            "UPDATE submissions SET phase = 'dispatching' WHERE id = ?1 AND phase = 'reserved'",
            [next.id.0.as_bytes().as_slice()],
        )?;
        if resume.is_some() {
            tx.execute(
                "UPDATE legacy_queue SET paused = FALSE, session_id = ?3, generation = ?4
                 WHERE id IN (SELECT id FROM submissions WHERE checkout_key = ?1 AND thread_id = ?2 AND phase = 'reserved')",
                params![key, thread.0, session, generation.as_slice()],
            )?;
        }
        tx.commit()?;
        state.active_submissions.insert(next.id);
        Ok(Some(LegacyDispatch {
            id: next.id,
            request,
            _write: SubmissionWrite {
                store: self.clone(),
                id: next.id,
            },
        }))
    }

    pub(crate) fn pause_legacy_queue(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<(), JournalError> {
        let state = self.inner.state();
        pause(&state.database, checkout, thread)?;
        Ok(())
    }

    pub(crate) fn fail_legacy_dispatch(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        id: RequestId,
        known_unsent: bool,
    ) -> Result<(), JournalError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if known_unsent {
            tx.execute(
                "UPDATE submissions SET phase = 'reserved'
                 WHERE id = ?1 AND checkout_key = ?2 AND thread_id = ?3 AND phase = 'dispatching'
                   AND EXISTS (SELECT 1 FROM legacy_queue AS l WHERE l.id = ?1)
                   AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = ?1)",
                params![id.0.as_bytes().as_slice(), checkout.storage_key(), thread.0],
            )?;
        }
        pause(&tx, checkout, thread)?;
        tx.commit()?;
        Ok(())
    }
}

fn pause(
    database: &Connection,
    checkout: &CheckoutIdentity,
    thread: &ThreadId,
) -> rusqlite::Result<()> {
    database.execute(
        "UPDATE legacy_queue SET paused = TRUE
         WHERE id IN (SELECT id FROM submissions WHERE checkout_key = ?1 AND thread_id = ?2 AND phase = 'reserved')",
        params![checkout.storage_key(), thread.0],
    )?;
    Ok(())
}

pub(super) fn insert_legacy_entry(
    tx: &Transaction<'_>,
    entry: &JournalEntry<'_>,
    owner: &ConnectionIdentity,
) -> rusqlite::Result<()> {
    let session = owner.workspace.session.0.as_bytes().as_slice();
    let generation = owner.generation.0.to_le_bytes();
    tx.execute(
        "INSERT INTO legacy_queue (id, session_id, generation, paused)
         VALUES (?1, ?4, ?5, EXISTS (
             SELECT 1 FROM legacy_queue AS l JOIN submissions AS s ON l.id = s.id
             WHERE s.checkout_key = ?2 AND s.thread_id = ?3 AND s.phase = 'reserved'
               AND (l.paused OR l.session_id <> ?4 OR l.generation <> ?5)
         ))",
        params![
            entry.id.0.as_bytes().as_slice(),
            entry.checkout.storage_key(),
            entry.thread.0,
            session,
            generation.as_slice()
        ],
    )?;
    Ok(())
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE legacy_queue (
           position INTEGER PRIMARY KEY AUTOINCREMENT,
           id BLOB NOT NULL UNIQUE REFERENCES submissions (id) ON DELETE CASCADE,
           session_id BLOB NOT NULL CHECK (length(session_id) = 16),
           generation BLOB NOT NULL CHECK (length(generation) = 8),
           paused INTEGER NOT NULL CHECK (paused IN (FALSE, TRUE))
         ) STRICT;",
    )
}
