use std::io;

use rusqlite::{OptionalExtension, Transaction, params};

use crate::{checkout::CheckoutIdentity, ipc::ComposerSelection};

use super::{AttachmentError, AttachmentStore};

impl AttachmentStore {
    pub fn composer_selection(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&str>,
    ) -> Result<Option<ComposerSelection>, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        let content: Option<String> = state.database.query_row(
            "SELECT selection FROM composer_selections WHERE checkout_key = ?1 AND thread_id = ?2
             UNION ALL SELECT selection FROM appkit_composer_preferences WHERE checkout_key = ?1 LIMIT 1",
            params![checkout.storage_key(), thread.unwrap_or_default()], |row| row.get(0),
        ).optional()?;
        content
            .map(|content| serde_json::from_str(&content).map_err(io::Error::other))
            .transpose()
            .map_err(Into::into)
    }

    pub fn save_composer_selection(
        &self,
        checkout: &CheckoutIdentity,
        thread: Option<&str>,
        selection: &ComposerSelection,
    ) -> Result<(), AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let content = serde_json::to_string(selection).map_err(io::Error::other)?;
        let state = self.inner.state();
        state.database.execute(
            "INSERT INTO composer_selections (checkout_key, thread_id, selection) VALUES (?1, ?2, ?3)
             ON CONFLICT (checkout_key, thread_id) DO UPDATE SET selection = excluded.selection",
            params![checkout.storage_key(), thread.unwrap_or_default(), content],
        )?;
        Ok(())
    }
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE composer_selections (
        checkout_key TEXT NOT NULL, thread_id TEXT NOT NULL,
        selection TEXT NOT NULL CHECK (json_valid(selection) AND json_type(selection) = 'object'),
        PRIMARY KEY (checkout_key, thread_id)
    ) STRICT, WITHOUT ROWID;",
    )
}
