use rusqlite::{Transaction, params};

use super::{AttachmentError, AttachmentStore};
use crate::{checkout::CheckoutIdentity, identity::ThreadId};

impl AttachmentStore {
    pub fn reserve_feedback(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        turn: &str,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "INSERT INTO desktop_turn_feedback (project_id, thread_id, turn_id, confirmed) VALUES (?1, ?2, ?3, 0)
             ON CONFLICT (project_id, thread_id, turn_id) DO NOTHING",
            params![checkout.storage_key(), thread.0, turn],
        )? == 1)
    }

    pub fn confirm_feedback(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        turn: &str,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state.database.execute(
            "UPDATE desktop_turn_feedback SET confirmed = 1 WHERE project_id = ?1 AND thread_id = ?2 AND turn_id = ?3",
            params![checkout.storage_key(), thread.0, turn],
        )?;
        Ok(())
    }

    pub fn release_feedback(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        turn: &str,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state.database.execute(
            "DELETE FROM desktop_turn_feedback WHERE project_id = ?1 AND thread_id = ?2 AND turn_id = ?3 AND confirmed = 0",
            params![checkout.storage_key(), thread.0, turn],
        )?;
        Ok(())
    }

    pub fn reserved_feedback(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<Vec<String>, AttachmentError> {
        let state = self.inner.state();
        let mut statement = state.database.prepare(
            "SELECT turn_id FROM desktop_turn_feedback WHERE project_id = ?1 AND thread_id = ?2 ORDER BY turn_id",
        )?;
        Ok(statement
            .query_map(params![checkout.storage_key(), thread.0], |row| row.get(0))?
            .collect::<Result<_, _>>()?)
    }
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_turn_feedback (
            project_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            turn_id TEXT NOT NULL,
            confirmed INTEGER NOT NULL CHECK (confirmed IN (0, 1)),
            PRIMARY KEY (project_id, thread_id, turn_id)
        ) STRICT, WITHOUT ROWID;",
    )
}
