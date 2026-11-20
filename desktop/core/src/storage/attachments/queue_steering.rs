use super::*;
use crate::{
    checkout::CheckoutIdentity, identity::TurnId, storage::drafts::DraftSave,
    workspace::ExecutionTarget,
};
use uuid::Uuid;

use super::queue_edits::split_queue_input;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QueueSteerPhase {
    Deleting,
    Detached,
    Steering,
}

impl QueueSteerPhase {
    fn name(self) -> &'static str {
        match self {
            Self::Deleting => "deleting",
            Self::Detached => "detached",
            Self::Steering => "steering",
        }
    }
}

#[derive(Debug)]
pub struct QueueSteeringReceipt {
    pub id: RequestId,
    pub target: ExecutionTarget,
    pub client_id: String,
    pub queued_id: Option<String>,
    pub input: Vec<Value>,
    pub phase: QueueSteerPhase,
}

impl AttachmentStore {
    pub fn queue_steering_receipts(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<Vec<QueueSteeringReceipt>, JournalError> {
        let state = self.inner.state();
        let mut statement = state.database.prepare(
            "SELECT id, turn_id, client_id, queued_id, input, phase FROM queue_steering
             WHERE checkout_key = ?1 AND thread_id = ?2 ORDER BY id",
        )?;
        let rows = statement.query_map(params![checkout.storage_key(), thread.0], |row| {
            Ok((
                row.get::<_, [u8; 16]>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
            ))
        })?;
        rows.map(|row| {
            let (id, turn, client_id, queued_id, input, phase) = row?;
            let phase = match phase.as_str() {
                "deleting" => QueueSteerPhase::Deleting,
                "detached" => QueueSteerPhase::Detached,
                "steering" => QueueSteerPhase::Steering,
                _ => return Err(JournalError::InvalidPhase),
            };
            Ok(QueueSteeringReceipt {
                id: RequestId(Uuid::from_bytes(id)),
                target: ExecutionTarget {
                    thread: thread.clone(),
                    turn: TurnId(turn),
                },
                client_id,
                queued_id,
                input: serde_json::from_str(&input)?,
                phase,
            })
        })
        .collect()
    }

    pub(crate) fn steering_is_reserved(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        client_id: &str,
    ) -> Result<bool, JournalError> {
        let state = self.inner.state();
        Ok(state.database.query_row(
            "SELECT EXISTS(SELECT 1 FROM queue_steering WHERE checkout_key = ?1 AND thread_id = ?2 AND client_id = ?3)",
            params![checkout.storage_key(), thread.0, client_id],
            |row| row.get(0),
        )?)
    }

    pub(crate) fn reserve_queue_steering(
        &self,
        checkout: &CheckoutIdentity,
        target: &ExecutionTarget,
        client_id: &str,
        queued_id: Option<&str>,
        input: &[Value],
    ) -> Result<QueueSteeringReceipt, JournalError> {
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let scope = checkout.storage_key();
        let phase = if queued_id.is_some() {
            QueueSteerPhase::Deleting
        } else {
            let legacy = Uuid::parse_str(client_id).map_err(|_| JournalError::InvalidPhase)?;
            let changed = tx.execute(
                "UPDATE submissions SET phase = 'dispatching'
                 WHERE id = ?1 AND checkout_key = ?2 AND thread_id = ?3 AND phase = 'reserved'
                   AND EXISTS (SELECT 1 FROM legacy_queue WHERE id = ?1)
                   AND NOT EXISTS (SELECT 1 FROM submission_outcomes WHERE id = ?1)",
                params![legacy.as_bytes().as_slice(), scope, target.thread.0],
            )?;
            if changed != 1 {
                return Err(JournalError::InvalidPhase);
            }
            QueueSteerPhase::Detached
        };
        let id = RequestId(Uuid::new_v4());
        tx.execute(
            "INSERT INTO queue_steering (id, checkout_key, thread_id, turn_id, client_id, queued_id, input, phase)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id.0.as_bytes().as_slice(), scope, target.thread.0, target.turn.0, client_id,
                queued_id, serde_json::to_string(input)?, phase.name()
            ],
        )?;
        tx.commit()?;
        Ok(QueueSteeringReceipt {
            id,
            target: target.clone(),
            client_id: client_id.to_owned(),
            queued_id: queued_id.map(str::to_owned),
            input: input.to_vec(),
            phase,
        })
    }

    pub(crate) fn transition_queue_steering(
        &self,
        checkout: &CheckoutIdentity,
        id: RequestId,
        from: QueueSteerPhase,
        to: Option<QueueSteerPhase>,
    ) -> Result<bool, JournalError> {
        let state = self.inner.state();
        let scope = checkout.storage_key();
        let id = id.0.as_bytes().as_slice();
        let changed = if let Some(to) = to {
            state.database.execute(
                "UPDATE queue_steering SET phase = ?4 WHERE id = ?1 AND checkout_key = ?2 AND phase = ?3",
                params![id, scope, from.name(), to.name()],
            )?
        } else {
            state.database.execute(
                "DELETE FROM queue_steering WHERE id = ?1 AND checkout_key = ?2 AND phase = ?3",
                params![id, scope, from.name()],
            )?
        };
        Ok(changed == 1)
    }

    pub(crate) fn observe_steering_message(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        turn: &TurnId,
        client_id: &str,
    ) -> Result<bool, JournalError> {
        let state = self.inner.state();
        let changed = state.database.execute(
            "DELETE FROM queue_steering WHERE checkout_key = ?1 AND thread_id = ?2 AND client_id = ?3
               AND (phase = 'deleting' OR (phase = 'steering' AND turn_id = ?4))",
            params![checkout.storage_key(), thread.0, client_id, turn.0],
        )?;
        Ok(changed == 1)
    }

    pub(crate) fn restore_detached_steering(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        id: RequestId,
    ) -> Result<DraftId, JournalError> {
        let draft_id = self.editable_thread_draft(thread)?;
        let mut state = self.inner.state();
        let tx = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = id.0.as_bytes().as_slice();
        let scope = checkout.storage_key();
        let (client, queued_id, input): (String, Option<String>, String) = tx
            .query_row(
                "SELECT client_id, queued_id, input FROM queue_steering
             WHERE id = ?1 AND checkout_key = ?2 AND thread_id = ?3 AND phase = 'detached'",
                params![id, scope, thread.0],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?
            .ok_or(JournalError::InvalidPhase)?;
        let draft = read_draft(&tx, draft_id)
            .map_err(AttachmentError::from)?
            .ok_or(AttachmentError::MissingDraft)?;
        let draft_key = draft_id.0.as_bytes().as_slice();
        if !draft.text.is_empty()
            || !draft.context.is_empty()
            || tx.query_row(
                "SELECT EXISTS (SELECT 1 FROM draft_attachments WHERE draft_id = ?1)
                     OR EXISTS (SELECT 1 FROM queue_edits WHERE draft_id = ?1)",
                [draft_key],
                |row| row.get::<_, bool>(0),
            )?
        {
            return Err(JournalError::PendingDraft);
        }
        let input: Vec<Value> = serde_json::from_str(&input)?;
        let (text, context) = split_queue_input(&input).ok_or(JournalError::InvalidPhase)?;
        let revision = draft.revision.next().ok_or(JournalError::InvalidPhase)?;
        let saved = save_in_transaction(
            &tx,
            draft_id,
            Some(draft.revision),
            revision,
            Some(text),
            Some(context),
        )
        .map_err(AttachmentError::from)?;
        if saved != DraftSave::Applied {
            return Err(JournalError::InvalidPhase);
        }
        if let Ok(request) = Uuid::parse_str(&client) {
            let request = request.as_bytes().as_slice();
            let owns = tx.query_row(
                "SELECT EXISTS (
                    SELECT 1 FROM submissions AS s LEFT JOIN queue_receipts AS q ON q.id = s.id
                    LEFT JOIN legacy_queue AS l ON l.id = s.id
                    WHERE s.id = ?1 AND s.checkout_key = ?2 AND s.thread_id = ?3 AND s.phase = 'dispatching'
                       AND NOT EXISTS (SELECT 1 FROM submission_outcomes AS o WHERE o.id = s.id)
                       AND ((?4 IS NULL AND l.id IS NOT NULL)
                         OR (?4 IS NOT NULL AND q.id IS NOT NULL AND NOT q.deleted AND (q.queued_id = ?4 OR q.queued_id IS NULL)))
                )",
                params![request, scope, thread.0, queued_id],
                |row| row.get::<_, bool>(0),
            )?;
            if owns {
                tx.execute(
                    "INSERT INTO draft_attachments (draft_id, blob_id)
                     SELECT ?1, blob_id FROM submission_attachments WHERE submission_id = ?2",
                    params![draft_key, request],
                )?;
                tx.execute(
                    "DELETE FROM submission_attachments WHERE submission_id = ?1",
                    [request],
                )?;
                if let Some(queued_id) = queued_id {
                    tx.execute(
                        "UPDATE queue_receipts SET queued_id = ?2, deleted = TRUE WHERE id = ?1",
                        params![request, queued_id],
                    )?;
                } else {
                    tx.execute(
                        "UPDATE submissions SET phase = 'unsent' WHERE id = ?1",
                        [request],
                    )?;
                }
            }
        }
        tx.execute("DELETE FROM queue_steering WHERE id = ?1", [id])?;
        tx.commit()?;
        Ok(draft_id)
    }
}

pub(in crate::storage) fn migrate(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    tx.execute_batch(
        "CREATE TABLE queue_steering (
           id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16),
           checkout_key TEXT NOT NULL,
           thread_id TEXT NOT NULL,
           turn_id TEXT NOT NULL CHECK (length(turn_id) > 0),
           client_id TEXT NOT NULL CHECK (length(client_id) > 0),
           queued_id TEXT CHECK (length(queued_id) > 0),
           input TEXT NOT NULL CHECK (json_valid(input) AND json_type(input) = 'array'),
           phase TEXT NOT NULL CHECK (phase IN ('deleting', 'detached', 'steering')),
           UNIQUE (checkout_key, thread_id, client_id)
         ) STRICT, WITHOUT ROWID;",
    )
}
