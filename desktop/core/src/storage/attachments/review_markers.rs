use rusqlite::{Transaction, params};

use crate::{
    checkout::CheckoutIdentity, git::turn_edits::AppKitReviewFingerprints, identity::ThreadId,
};

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

    pub fn project_appkit_review(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
        turn: &str,
        origin: &str,
        legacy: &AppKitReviewFingerprints,
        fingerprints: &[String],
    ) -> Result<(), AttachmentError> {
        let Some(file) = fingerprints.first() else {
            return Ok(());
        };
        let candidates = std::iter::once((-1, "", legacy.file.as_str(), file)).chain(
            legacy.hunks.iter().filter_map(|(index, name, digest)| {
                Some((
                    i64::try_from(*index).ok()?,
                    name.as_str(),
                    digest.as_str(),
                    fingerprints.get(index + 1)?,
                ))
            }),
        );
        let mut state = self.inner.state();
        let transaction = state.database.transaction()?;
        let key = checkout.storage_key();
        for (index, hunk, original_digest, fingerprint) in candidates {
            let removed = transaction.execute(
                "DELETE FROM appkit_review_markers WHERE checkout_key = ?1 AND thread_id = ?2
                 AND turn_id = ?3 AND path = ?4 AND hunk = ?5 AND fingerprint = ?6",
                params![key, thread.0, turn, legacy.path, hunk, original_digest],
            )?;
            if removed != 0 {
                transaction.execute(
                    "INSERT OR IGNORE INTO desktop_review_markers SELECT ?1, ?2, ?3
                     WHERE NOT EXISTS (SELECT 1 FROM appkit_review_decisions WHERE origin = ?1 AND hunk = ?2)",
                    params![origin, index, fingerprint],
                )?;
            }
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn set_review_marker(
        &self,
        origin: &str,
        hunk: i64,
        fingerprint: &str,
        reviewed: bool,
    ) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state.database.transaction()?;
        transaction.execute(
            "INSERT OR IGNORE INTO appkit_review_decisions VALUES (?1, ?2)",
            params![origin, hunk],
        )?;
        if reviewed {
            transaction.execute(
                "INSERT INTO desktop_review_markers VALUES (?1, ?2, ?3)
                 ON CONFLICT (origin, hunk) DO UPDATE SET fingerprint = excluded.fingerprint",
                params![origin, hunk, fingerprint],
            )?;
        } else {
            transaction.execute(
                "DELETE FROM desktop_review_markers WHERE origin = ?1 AND hunk = ?2 AND fingerprint = ?3",
                params![origin, hunk, fingerprint],
            )?;
        }
        transaction.commit()?;
        Ok(())
    }
}
