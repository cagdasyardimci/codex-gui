use std::path::{Path, PathBuf};

use rusqlite::{OptionalExtension, Transaction, TransactionBehavior, params};
use uuid::Uuid;

use crate::{
    checkout::CheckoutIdentity,
    identity::ThreadId,
    storage::drafts::{
        DraftId, DraftPatch, DraftRevision, DraftSave, StoredDraft, read_draft, save_draft,
        save_in_transaction,
    },
};

use super::{AttachmentError, AttachmentStore};

pub struct DesktopSelection {
    pub project: Option<StoredProject>,
    pub thread: Option<ThreadId>,
    pub source_draft: DraftId,
}

pub struct StoredProject {
    path: PathBuf,
    directory_key: String,
}

impl StoredProject {
    pub fn restore(&self) -> Option<CheckoutIdentity> {
        let checkout = CheckoutIdentity::capture(&self.path).ok()?;
        (checkout.storage_key() == self.directory_key).then_some(checkout)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl AttachmentStore {
    pub fn desktop_selection(&self) -> Result<DesktopSelection, AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let selection = transaction.query_row(
            "SELECT project_path, project_key, thread_id, source_draft FROM desktop_selection WHERE slot = 1",
            [],
            |row| {
                let path: Option<String> = row.get(0)?;
                let key: Option<String> = row.get(1)?;
                let thread: Option<String> = row.get(2)?;
                let draft: [u8; 16] = row.get(3)?;
                Ok(DesktopSelection {
                    project: path.zip(key).map(|(path, directory_key)| StoredProject {
                        path: PathBuf::from(path), directory_key,
                    }),
                    thread: thread.map(ThreadId),
                    source_draft: DraftId(Uuid::from_bytes(draft)),
                })
            },
        ).optional()?;
        let selection = match selection {
            Some(selection) => selection,
            None => {
                let source_draft = empty_draft(&transaction)?;
                transaction.execute(
                    "INSERT INTO desktop_selection (slot, source_draft) VALUES (1, ?1)",
                    [source_draft.0.as_bytes().as_slice()],
                )?;
                DesktopSelection {
                    project: None,
                    thread: None,
                    source_draft,
                }
            }
        };
        transaction.commit()?;
        Ok(selection)
    }

    pub fn save_desktop_selection(
        &self,
        project: Option<(&Path, &CheckoutIdentity)>,
        thread: Option<&ThreadId>,
    ) -> Result<(), AttachmentError> {
        let (path, identity) = match project {
            Some((path, checkout)) => {
                checkout
                    .validate_reported(path)
                    .map_err(std::io::Error::other)?;
                let path = path.to_str().ok_or_else(|| {
                    std::io::Error::new(
                        std::io::ErrorKind::InvalidInput,
                        "Codex project path is not Unicode",
                    )
                })?;
                (Some(path), Some(checkout.storage_key()))
            }
            None => (None, None),
        };
        let state = self.inner.state();
        state.database.execute(
            "UPDATE desktop_selection SET project_path = ?1, project_key = ?2, thread_id = ?3 WHERE slot = 1",
            params![path, identity, thread.map(|thread| &thread.0)],
        )?;
        Ok(())
    }

    pub fn editable_thread_draft(&self, thread: &ThreadId) -> Result<DraftId, AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let existing = transaction
            .query_row(
                "SELECT draft_id FROM thread_drafts WHERE thread_id = ?1",
                [&thread.0],
                |row| row.get::<_, [u8; 16]>(0),
            )
            .optional()?;
        let draft = match existing {
            Some(existing) => DraftId(Uuid::from_bytes(existing)),
            None => {
                let draft = empty_draft(&transaction)?;
                transaction.execute(
                    "INSERT INTO thread_drafts (thread_id, draft_id) VALUES (?1, ?2)",
                    params![thread.0, draft.0.as_bytes().as_slice()],
                )?;
                draft
            }
        };
        transaction.commit()?;
        Ok(draft)
    }

    pub fn read_editor_draft(&self, draft: DraftId) -> Result<StoredDraft, AttachmentError> {
        let state = self.inner.state();
        read_draft(&state.database, draft)?.ok_or(AttachmentError::MissingDraft)
    }

    pub fn save_editor_text(&self, draft: DraftId, text: String) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        let current = read_draft(&state.database, draft)?.ok_or(AttachmentError::MissingDraft)?;
        if current.text == text {
            return Ok(());
        }
        let revision = current
            .revision
            .next()
            .ok_or_else(|| std::io::Error::other("draft revision exhausted"))?;
        let patch = DraftPatch {
            text: Some(text),
            context: None,
        };
        let outcome = save_draft(
            &mut state.database,
            draft,
            Some(current.revision),
            revision,
            &patch,
        )?;
        if outcome != DraftSave::Applied {
            return Err(std::io::Error::other("draft revision moved during editor save").into());
        }
        Ok(())
    }
}

fn empty_draft(transaction: &Transaction<'_>) -> Result<DraftId, AttachmentError> {
    let draft = DraftId(Uuid::new_v4());
    save_in_transaction(transaction, draft, None, DraftRevision::INITIAL, None, None)?;
    Ok(draft)
}

pub(in crate::storage) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE desktop_selection (
            slot INTEGER PRIMARY KEY CHECK (slot = 1),
            project_path TEXT,
            project_key TEXT,
            thread_id TEXT CHECK (thread_id IS NULL OR project_path IS NOT NULL),
            source_draft BLOB NOT NULL REFERENCES drafts (id),
            CHECK ((project_path IS NULL) = (project_key IS NULL))
        ) STRICT;",
    )
}
