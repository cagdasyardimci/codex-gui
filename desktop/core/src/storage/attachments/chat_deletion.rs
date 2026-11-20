use std::collections::HashSet;

use rusqlite::{Transaction, TransactionBehavior};

use super::{AttachmentError, AttachmentStore, BlobId, replace_references};
use crate::identity::ThreadId;

impl AttachmentStore {
    pub fn prepare_chat_deletion(&self, thread: &ThreadId) -> Result<bool, AttachmentError> {
        let state = self.inner.state();
        Ok(state.database.execute(
            "INSERT INTO desktop_chat_deletions (thread_id, confirmed) VALUES (?1, 0)
             ON CONFLICT (thread_id) DO NOTHING",
            [&thread.0],
        )? == 1)
    }

    pub fn release_chat_deletion(&self, thread: &ThreadId) -> Result<(), AttachmentError> {
        let state = self.inner.state();
        state.database.execute(
            "DELETE FROM desktop_chat_deletions WHERE thread_id = ?1 AND confirmed = 0",
            [&thread.0],
        )?;
        Ok(())
    }

    pub fn confirm_chat_deletion(&self, thread: &ThreadId) -> Result<(), AttachmentError> {
        use rusqlite::OptionalExtension;

        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let draft: Option<Vec<u8>> = transaction
            .query_row(
                "SELECT draft_id FROM thread_drafts WHERE thread_id = ?1",
                [&thread.0],
                |row| row.get(0),
            )
            .optional()?;
        let mut released = Vec::<BlobId>::new();
        if let Some(draft) = draft {
            released =
                replace_references(&transaction, &self.inner.blobs, &draft, std::iter::empty())?;
            transaction.execute("DELETE FROM drafts WHERE id = ?1", [&draft])?;
        }
        transaction.execute(
            "DELETE FROM desktop_sidebar_chats WHERE thread_id = ?1",
            [&thread.0],
        )?;
        transaction.execute(
            "UPDATE desktop_chat_deletions SET confirmed = 1 WHERE thread_id = ?1",
            [&thread.0],
        )?;
        transaction.commit()?;
        state.candidates.extend(released);
        Ok(())
    }

    pub fn deleted_chats(&self) -> Result<HashSet<ThreadId>, AttachmentError> {
        let state = self.inner.state();
        let mut statement = state
            .database
            .prepare("SELECT thread_id FROM desktop_chat_deletions WHERE confirmed = 1")?;
        Ok(statement
            .query_map([], |row| row.get(0).map(ThreadId))?
            .collect::<Result<_, _>>()?)
    }
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_chat_deletions (
            thread_id TEXT NOT NULL PRIMARY KEY,
            confirmed INTEGER NOT NULL CHECK (confirmed IN (0, 1))
        ) STRICT, WITHOUT ROWID;",
    )
}
