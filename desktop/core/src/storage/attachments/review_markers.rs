use rusqlite::{Transaction, params};

use super::{AttachmentError, AttachmentStore};

pub(crate) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_review_markers (
            origin TEXT NOT NULL,
            hunk INTEGER NOT NULL,
            fingerprint TEXT NOT NULL,
            PRIMARY KEY (origin, hunk)
        ) WITHOUT ROWID;",
    )
}

impl AttachmentStore {
    pub fn review_markers(&self, origin: &str) -> Result<Vec<(i64, String)>, AttachmentError> {
        let state = self.inner.state();
        let mut statement = state
            .database
            .prepare("SELECT hunk, fingerprint FROM desktop_review_markers WHERE origin = ?1")?;
        let rows = statement.query_map([origin], |row| Ok((row.get(0)?, row.get(1)?)))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn set_review_marker(
        &self,
        origin: &str,
        hunk: i64,
        fingerprint: &str,
        reviewed: bool,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        if reviewed {
            state.database.execute(
                "INSERT INTO desktop_review_markers VALUES (?1, ?2, ?3)
                 ON CONFLICT (origin, hunk) DO UPDATE SET fingerprint = excluded.fingerprint",
                params![origin, hunk, fingerprint],
            )?;
        } else {
            state.database.execute(
                "DELETE FROM desktop_review_markers WHERE origin = ?1 AND hunk = ?2 AND fingerprint = ?3",
                params![origin, hunk, fingerprint],
            )?;
        }
        Ok(())
    }
}
