use std::sync::Arc;

use rusqlite::{OptionalExtension, Transaction, TransactionBehavior, params};
use serde_json::json;
use uuid::Uuid;

use crate::{checkout::CheckoutIdentity, identity::TurnId};

use super::*;

pub enum RecordedAttachment {
    Image { title: String, lease: BlobLease },
    Mention { name: String, relative: String },
}

impl AttachmentStore {
    pub fn stage_fork_revision(
        &self,
        checkout: &CheckoutIdentity,
        source_thread: &ThreadId,
        source_turn: &TurnId,
        text: &str,
        attachments: &[RecordedAttachment],
    ) -> Result<DraftId, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        if attachments.len() > composer::MAX_COMPOSER_ATTACHMENTS {
            return Err(io::Error::other("too many recorded prompt attachments").into());
        }
        let mut blobs = Vec::new();
        let mut context = Vec::new();
        for attachment in attachments {
            let id = Uuid::new_v4().to_string();
            match attachment {
                RecordedAttachment::Image { title, lease } => {
                    if !Arc::ptr_eq(&self.inner, &lease.store) {
                        return Err(AttachmentError::ForeignLease);
                    }
                    blobs.push(lease.id);
                    let path = lease
                        .path()
                        .into_os_string()
                        .into_string()
                        .map_err(|_| io::Error::other("attachment path is not Unicode"))?;
                    context.push(json!({"id": id, "kind": "image", "title": title, "path": path}));
                }
                RecordedAttachment::Mention { name, relative } => {
                    context.push(json!({"id": id, "kind": "fileReference", "title": name,
                        "recordedMentionName": name, "path": relative}));
                }
            }
        }
        let draft = DraftId(Uuid::new_v4());
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        save_in_transaction(
            &transaction,
            draft,
            None,
            DraftRevision::INITIAL,
            Some(text),
            Some(&context),
        )?;
        replace_references(
            &transaction,
            &self.inner.blobs,
            draft.0.as_bytes(),
            blobs.into_iter(),
        )?;
        transaction.execute(
            "INSERT INTO fork_revisions (draft_id, checkout_key, source_thread, source_turn)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                draft.0.as_bytes(),
                checkout.storage_key(),
                source_thread.0,
                source_turn.0
            ],
        )?;
        transaction.commit()?;
        Ok(draft)
    }

    pub fn bind_fork_revision(
        &self,
        checkout: &CheckoutIdentity,
        draft: DraftId,
        target: &ThreadId,
    ) -> Result<bool, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let saved = transaction.execute(
            "UPDATE fork_revisions SET target_thread = ?3 WHERE draft_id = ?1 AND checkout_key = ?2
             AND (target_thread IS NULL OR target_thread = ?3) AND source_thread <> ?3",
            params![draft.0.as_bytes(), checkout.storage_key(), target.0],
        )?;
        if saved == 0 {
            return Err(AttachmentError::ConflictingThreadDraft);
        }
        let existing: Option<[u8; 16]> = transaction
            .query_row(
                "SELECT draft_id FROM thread_drafts WHERE thread_id = ?1",
                [&target.0],
                |row| row.get(0),
            )
            .optional()?;
        let owned = match existing {
            None => {
                transaction.execute(
                    "INSERT INTO thread_drafts (thread_id, draft_id) VALUES (?1, ?2)",
                    params![target.0, draft.0.as_bytes()],
                )?;
                true
            }
            Some(existing) => existing == *draft.0.as_bytes(),
        };
        transaction.commit()?;
        Ok(owned)
    }

    pub fn has_pending_fork_revision(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
    ) -> Result<bool, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        Ok(state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM fork_revisions WHERE checkout_key = ?1
               AND source_thread = ?2 AND target_thread IS NULL)",
            params![checkout.storage_key(), source.0],
            |row| row.get(0),
        )?)
    }

    pub fn is_literal_fork_revision(
        &self,
        checkout: &CheckoutIdentity,
        target: &str,
        draft: DraftId,
    ) -> Result<bool, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        Ok(state.database.query_row(
            "SELECT EXISTS (SELECT 1 FROM fork_revisions WHERE checkout_key = ?1 AND target_thread = ?2
               AND draft_id = ?3 AND NOT EXISTS (
                   SELECT 1 FROM submissions AS s JOIN submission_outcomes AS o ON o.id = s.id
                   WHERE s.checkout_key = ?1 AND s.thread_id = ?2 AND s.draft_id = ?3 AND o.turn_id IS NOT NULL
               ))",
            params![checkout.storage_key(), target, draft.0.as_bytes()],
            |row| row.get(0),
        )?)
    }

    pub fn conversation_fork_receipt(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
    ) -> Result<Option<Uuid>, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        let receipt: Option<[u8; 16]> = state.database.query_row(
            "SELECT operation FROM conversation_forks WHERE checkout_key = ?1 AND source_thread = ?2",
            params![checkout.storage_key(), source.0], |row| row.get(0),
        ).optional()?;
        Ok(receipt.map(Uuid::from_bytes))
    }

    pub fn reserve_conversation_fork(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
        operation: Uuid,
    ) -> Result<bool, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        Ok(state.database.execute(
            "INSERT INTO conversation_forks (checkout_key, source_thread, operation) VALUES (?1, ?2, ?3)
             ON CONFLICT(checkout_key, source_thread) DO NOTHING",
            params![checkout.storage_key(), source.0, operation.as_bytes()],
        )? == 1)
    }

    pub fn retire_conversation_fork(
        &self,
        checkout: &CheckoutIdentity,
        source: &ThreadId,
        operation: Uuid,
    ) -> Result<bool, AttachmentError> {
        checkout.revalidate().map_err(io::Error::other)?;
        let state = self.inner.state();
        Ok(state.database.execute(
            "DELETE FROM conversation_forks WHERE checkout_key = ?1 AND source_thread = ?2 AND operation = ?3",
            params![checkout.storage_key(), source.0, operation.as_bytes()],
        )? == 1)
    }
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE fork_revisions (
            draft_id BLOB NOT NULL PRIMARY KEY REFERENCES drafts (id) ON DELETE CASCADE,
            checkout_key TEXT NOT NULL,
            source_thread TEXT NOT NULL CHECK (length(source_thread) > 0),
            source_turn TEXT NOT NULL CHECK (length(source_turn) > 0),
            target_thread TEXT
        ) STRICT, WITHOUT ROWID;
        CREATE UNIQUE INDEX unbound_fork_revision ON fork_revisions (checkout_key, source_thread)
        WHERE target_thread IS NULL;",
    )
}

pub(in crate::storage) fn migrate_fork_receipts(
    transaction: &Transaction<'_>,
) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE conversation_forks (
            checkout_key TEXT NOT NULL,
            source_thread TEXT NOT NULL CHECK (length(source_thread) > 0),
            operation BLOB NOT NULL CHECK (length(operation) = 16),
            PRIMARY KEY (checkout_key, source_thread)
        ) STRICT, WITHOUT ROWID;",
    )
}
