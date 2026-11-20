use std::collections::HashSet;

use rusqlite::{Transaction, params};
use uuid::Uuid;

use crate::files::FileRevision;

use super::{AttachmentError, AttachmentStore};

pub(crate) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_usage_reset_attempts (
            account TEXT NOT NULL, credit TEXT NOT NULL, attempt BLOB NOT NULL,
            PRIMARY KEY (account, credit)
        ) WITHOUT ROWID;",
    )
}

impl AttachmentStore {
    pub fn reserved_usage_resets(&self, account: &str) -> Result<HashSet<String>, AttachmentError> {
        let state = self.inner.state();
        let mut query = state
            .database
            .prepare("SELECT credit FROM desktop_usage_reset_attempts WHERE account = ?1")?;
        let rows = query.query_map([account_key(account)], |row| row.get(0))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn reserve_usage_reset(
        &self,
        account: &str,
        credit: &str,
        attempt: Uuid,
    ) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "INSERT OR IGNORE INTO desktop_usage_reset_attempts VALUES (?1, ?2, ?3)",
            params![account_key(account), credit, attempt.as_bytes().as_slice()],
        )? == 1)
    }

    pub fn release_usage_reset(
        &self,
        account: &str,
        credit: &str,
        attempt: Uuid,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state.database.execute(
            "DELETE FROM desktop_usage_reset_attempts WHERE account = ?1 AND credit = ?2 AND attempt = ?3",
            params![account_key(account), credit, attempt.as_bytes().as_slice()],
        )?;
        Ok(())
    }
}

fn account_key(account: &str) -> String {
    FileRevision::from_bytes(account.as_bytes()).digest
}
