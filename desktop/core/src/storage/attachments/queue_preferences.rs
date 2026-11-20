use super::*;
use crate::checkout::CheckoutIdentity;

impl AttachmentStore {
    pub fn queue_enabled(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> rusqlite::Result<bool> {
        Ok(self
            .inner
            .state()
            .database
            .query_row(
                "SELECT enabled FROM queue_preferences WHERE checkout_key = ?1 AND thread_id = ?2",
                params![checkout.storage_key(), thread.0],
                |row| row.get(0),
            )
            .optional()?
            .unwrap_or(true))
    }

    pub fn set_queue_enabled(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        enabled: bool,
    ) -> rusqlite::Result<()> {
        self.inner.state().database.execute(
            "INSERT INTO queue_preferences (checkout_key, thread_id, enabled) VALUES (?1, ?2, ?3)
             ON CONFLICT (checkout_key, thread_id) DO UPDATE SET enabled = excluded.enabled",
            params![checkout.storage_key(), thread.0, enabled],
        )?;
        Ok(())
    }
}

pub(in crate::storage) fn migrate(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    tx.execute_batch(
        "CREATE TABLE queue_preferences (
           checkout_key TEXT NOT NULL,
           thread_id TEXT NOT NULL,
           enabled INTEGER NOT NULL CHECK (enabled IN (FALSE, TRUE)),
           PRIMARY KEY (checkout_key, thread_id)
         ) STRICT, WITHOUT ROWID;
         ALTER TABLE legacy_queue ADD COLUMN sort_key INTEGER CHECK (sort_key > 0);",
    )
}
