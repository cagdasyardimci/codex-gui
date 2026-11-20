use rusqlite::Transaction;

use super::{AttachmentError, AttachmentStore};

pub const REQUIRED_EFFORTS: &[&str] = &["low", "medium", "high", "xhigh"];

pub(crate) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_hidden_reasoning_efforts (effort TEXT PRIMARY KEY) WITHOUT ROWID;",
    )
}

impl AttachmentStore {
    pub fn hidden_reasoning_efforts(&self) -> Result<Vec<String>, AttachmentError> {
        let state = self.inner.state();
        let mut read = state
            .database
            .prepare("SELECT effort FROM desktop_hidden_reasoning_efforts ORDER BY effort")?;
        let rows = read.query_map([], |row| row.get::<_, String>(0))?;
        Ok(rows
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .filter(|effort| !REQUIRED_EFFORTS.contains(&effort.as_str()))
            .collect())
    }

    pub fn set_effort_visibility(
        &self,
        effort: &str,
        visible: bool,
    ) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        if visible {
            state.database.execute(
                "DELETE FROM desktop_hidden_reasoning_efforts WHERE effort = ?1",
                [effort],
            )?;
        } else if !REQUIRED_EFFORTS.contains(&effort) {
            state.database.execute(
                "INSERT OR IGNORE INTO desktop_hidden_reasoning_efforts (effort) VALUES (?1)",
                [effort],
            )?;
        }
        Ok(())
    }
}
