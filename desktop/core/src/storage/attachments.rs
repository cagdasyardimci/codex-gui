use std::{
    collections::{BTreeSet, HashMap, HashSet},
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
};

use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};
use serde_json::Value;
use sha2::{Digest, Sha256};
use tempfile::Builder;
use thiserror::Error;

use crate::identity::{RequestId, ThreadId};

use super::{
    DatabaseOpenError,
    drafts::{DraftId, DraftRevision, DraftStoreError, read_draft, save_in_transaction},
    open_workspace_database,
};

const PARTIAL_PREFIX: &str = ".partial-";

pub mod appkit_drafts;
pub mod composer;
pub(super) mod exit_recovery;
pub(super) mod legacy_queue;
pub mod navigation;
pub mod queue_edits;
pub(super) mod queue_preferences;
pub(super) mod queue_steering;
mod submissions;
pub use exit_recovery::ExitOwner;
pub use legacy_queue::{LegacyQueueEntry, LegacyQueueStatus};
pub use queue_steering::{QueueSteerPhase, QueueSteeringReceipt};
pub(crate) use submissions::{
    JournalEntry, JournalKind, JournalOutcome, JournalPhase, PendingSubmission, SubmissionWrite,
};
pub use submissions::{JournalError, SubmissionAcknowledgement};
pub(super) use submissions::{
    migrate_queue_deletions, migrate_queue_receipts, migrate_submission_checkout,
    migrate_submission_outcomes, migrate_submissions,
};

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct BlobId([u8; 32]);

impl BlobId {
    fn path(self, directory: &Path) -> PathBuf {
        directory.join(hex::encode(self.0))
    }
}

#[derive(Debug, Error)]
pub enum AttachmentError {
    #[error(transparent)]
    Disk(#[from] io::Error),
    #[error(transparent)]
    Database(#[from] rusqlite::Error),
    #[error(transparent)]
    OpenDatabase(#[from] DatabaseOpenError),
    #[error("could not take exclusive ownership of the attachment directory: {0}")]
    Lock(#[from] fs::TryLockError),
    #[error("attachment {0:?} is missing")]
    Missing(BlobId),
    #[error("attachment {0:?} does not match its stored size or file type")]
    InvalidFile(BlobId),
    #[error("the draft no longer owns a storage record")]
    MissingDraft,
    #[error("the captured attachment belongs to a different workspace store")]
    ForeignLease,
    #[error("the image or its annotations changed since the editor opened")]
    StaleAnnotations,
    #[error("the prepared thread or draft already has a different binding")]
    ConflictingThreadDraft,
    #[error(transparent)]
    Draft(#[from] DraftStoreError),
}

#[derive(Clone)]
pub struct AttachmentStore {
    inner: Arc<StoreInner>,
}

struct StoreInner {
    blobs: PathBuf,
    staging: PathBuf,
    state: Mutex<StoreState>,
    owner: File,
}

impl Drop for StoreInner {
    fn drop(&mut self) {
        // Release the profile lock even if a concurrent fork still holds the descriptor.
        let _ = self.owner.unlock();
    }
}

struct StoreState {
    database: Connection,
    leases: HashMap<BlobId, usize>,
    candidates: BTreeSet<BlobId>,
    active_submissions: HashSet<RequestId>,
}

pub struct BlobLease {
    id: BlobId,
    store: Arc<StoreInner>,
}

impl BlobLease {
    pub fn id(&self) -> BlobId {
        self.id
    }

    pub fn path(&self) -> PathBuf {
        self.id.path(&self.store.blobs)
    }
}

impl Drop for BlobLease {
    fn drop(&mut self) {
        let mut state = self.store.state();
        let leases = state
            .leases
            .get_mut(&self.id)
            .expect("active attachment lease");
        *leases -= 1;
        if *leases == 0 {
            state.leases.remove(&self.id);
            state.candidates.insert(self.id);
        }
    }
}

impl StoreInner {
    fn state(&self) -> MutexGuard<'_, StoreState> {
        self.state.lock().expect("attachment store lock poisoned")
    }
}

impl AttachmentStore {
    pub fn open(database_path: &Path) -> Result<Self, AttachmentError> {
        let database = open_workspace_database(database_path)?;
        let root = attachment_root(&fs::canonicalize(database_path)?);
        create_owned_directory(&root)?;
        let owner = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(root.join(".owner.lock"))?;
        owner.try_lock()?;
        let blobs = root.join("blobs");
        let staging = root.join("staging");
        create_owned_directory(&blobs)?;
        create_owned_directory(&staging)?;
        sync_directory(&root)?;
        clean_partial_files(&staging)?;
        let candidates = recovery_candidates(&database, &blobs)?;

        let store = Self {
            inner: Arc::new(StoreInner {
                blobs,
                staging,
                state: Mutex::new(StoreState {
                    database,
                    candidates,
                    leases: HashMap::new(),
                    active_submissions: HashSet::new(),
                }),
                owner,
            }),
        };
        store.collect()?;
        Ok(store)
    }

    pub fn stage(&self, mut input: impl Read) -> Result<BlobLease, AttachmentError> {
        let mut temporary = Builder::new()
            .prefix(PARTIAL_PREFIX)
            .tempfile_in(&self.inner.staging)?;
        let mut hasher = Sha256::new();
        let mut buffer = [0; 64 * 1024];
        loop {
            let count = match input.read(&mut buffer) {
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                result => result?,
            };
            if count == 0 {
                break;
            }
            temporary.write_all(&buffer[..count])?;
            hasher.update(&buffer[..count]);
        }
        let id = BlobId(hasher.finalize().into());
        let size = temporary.as_file().metadata()?.len();
        let size_in_database = i64::try_from(size).map_err(|_| AttachmentError::InvalidFile(id))?;
        temporary.as_file().sync_all()?;
        let mut state = self.inner.state();
        let path = id.path(&self.inner.blobs);
        match fs::symlink_metadata(&path) {
            Ok(metadata) => verify_file(id, &metadata, size)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                temporary
                    .persist_noclobber(&path)
                    .map_err(|error| error.error)?;
                sync_directory(&self.inner.blobs)?;
            }
            Err(error) => return Err(error.into()),
        }
        state.database.execute(
            "INSERT INTO attachment_blobs (id, size) VALUES (?1, ?2)
             ON CONFLICT (id) DO NOTHING",
            params![id.0.as_slice(), size_in_database],
        )?;
        Ok(self.retain(&mut state, id))
    }

    pub fn lease(&self, id: BlobId) -> Result<BlobLease, AttachmentError> {
        let mut state = self.inner.state();
        verify_saved_file(&state.database, &self.inner.blobs, id)?;
        Ok(self.retain(&mut state, id))
    }

    fn retain(&self, state: &mut StoreState, id: BlobId) -> BlobLease {
        *state.leases.entry(id).or_default() += 1;
        BlobLease {
            id,
            store: self.inner.clone(),
        }
    }

    pub fn replace_draft_references(
        &self,
        draft: DraftId,
        blobs: &[BlobId],
    ) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = draft.0.as_bytes().as_slice();
        let exists: bool = transaction.query_row(
            "SELECT EXISTS (SELECT 1 FROM drafts WHERE id = ?1)",
            [id],
            |row| row.get(0),
        )?;
        if !exists {
            return Err(AttachmentError::MissingDraft);
        }

        let removed =
            replace_references(&transaction, &self.inner.blobs, id, blobs.iter().copied())?;
        transaction.commit()?;
        state.candidates.extend(removed);
        Ok(())
    }

    pub(crate) fn bind_thread_draft(
        &self,
        thread: &ThreadId,
        draft: DraftId,
        revision: DraftRevision,
        text: &str,
        context: &[Value],
        leases: &[BlobLease],
    ) -> Result<(), AttachmentError> {
        if leases
            .iter()
            .any(|lease| !Arc::ptr_eq(&self.inner, &lease.store))
        {
            return Err(AttachmentError::ForeignLease);
        }
        let mut state = self.inner.state();
        let transaction = state
            .database
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let id = draft.0.as_bytes().as_slice();
        let binding = transaction
            .query_row(
                "SELECT thread_id, draft_id FROM thread_drafts
                 WHERE thread_id = ?1 OR draft_id = ?2
                 LIMIT 1",
                params![thread.0, id],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, [u8; 16]>(1)?)),
            )
            .optional()?;
        if let Some((bound_thread, bound_draft)) = binding {
            return if bound_thread == thread.0 && bound_draft == *draft.0.as_bytes() {
                Ok(())
            } else {
                Err(AttachmentError::ConflictingThreadDraft)
            };
        }

        let current = read_draft(&transaction, draft)?.map(|saved| saved.revision);
        if current.is_none_or(|saved| saved < revision) {
            save_in_transaction(
                &transaction,
                draft,
                current,
                revision,
                Some(text),
                Some(context),
            )?;
        }
        let removed = if current.is_none_or(|saved| saved <= revision) {
            replace_references(
                &transaction,
                &self.inner.blobs,
                id,
                leases.iter().map(BlobLease::id),
            )?
        } else {
            Vec::new()
        };
        transaction.execute(
            "INSERT INTO thread_drafts (thread_id, draft_id) VALUES (?1, ?2)",
            params![thread.0, id],
        )?;
        navigation::promote_source(&transaction, draft, thread)?;
        transaction.commit()?;
        state.candidates.extend(removed);
        Ok(())
    }

    pub fn collect(&self) -> Result<(), AttachmentError> {
        let mut state = self.inner.state();
        while let Some(id) = state.candidates.pop_first() {
            if state.leases.contains_key(&id) {
                continue;
            }
            if let Err(error) = collect_one(&mut state.database, &self.inner.blobs, id) {
                state.candidates.insert(id);
                return Err(error);
            }
        }
        Ok(())
    }
}

fn replace_references(
    transaction: &Transaction<'_>,
    root: &Path,
    draft_id: &[u8],
    blobs: impl Iterator<Item = BlobId>,
) -> Result<Vec<BlobId>, AttachmentError> {
    let requested: BTreeSet<_> = blobs.collect();
    let existing = {
        let mut statement =
            transaction.prepare("SELECT blob_id FROM draft_attachments WHERE draft_id = ?1")?;
        statement
            .query_map([draft_id], |row| row.get::<_, [u8; 32]>(0).map(BlobId))?
            .collect::<Result<BTreeSet<_>, _>>()?
    };
    let removed: Vec<_> = existing.difference(&requested).copied().collect();
    for blob in requested.difference(&existing) {
        verify_saved_file(transaction, root, *blob)?;
        transaction.execute(
            "INSERT INTO draft_attachments (draft_id, blob_id) VALUES (?1, ?2)",
            params![draft_id, blob.0.as_slice()],
        )?;
    }
    for blob in &removed {
        transaction.execute(
            "DELETE FROM draft_attachments WHERE draft_id = ?1 AND blob_id = ?2",
            params![draft_id, blob.0.as_slice()],
        )?;
    }
    Ok(removed)
}

pub(super) fn migrate_thread_drafts(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE thread_drafts (
            thread_id TEXT NOT NULL PRIMARY KEY CHECK (length(thread_id) > 0),
            draft_id BLOB NOT NULL UNIQUE REFERENCES drafts (id) ON DELETE CASCADE
        ) STRICT, WITHOUT ROWID;",
    )
}

fn verify_file(id: BlobId, metadata: &fs::Metadata, size: u64) -> Result<(), AttachmentError> {
    if !metadata.is_file() || metadata.len() != size {
        return Err(AttachmentError::InvalidFile(id));
    }
    Ok(())
}

fn verify_saved_file(
    database: &Connection,
    blobs: &Path,
    id: BlobId,
) -> Result<(), AttachmentError> {
    let size: i64 = database
        .query_row(
            "SELECT size FROM attachment_blobs WHERE id = ?1",
            [id.0.as_slice()],
            |row| row.get(0),
        )
        .optional()?
        .ok_or(AttachmentError::Missing(id))?;
    let size = u64::try_from(size).map_err(|_| AttachmentError::InvalidFile(id))?;
    let metadata = fs::symlink_metadata(id.path(blobs))?;
    verify_file(id, &metadata, size)
}

fn collect_one(database: &mut Connection, blobs: &Path, id: BlobId) -> Result<(), AttachmentError> {
    let transaction = database.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let owned: bool = transaction.query_row(
        "SELECT EXISTS (SELECT 1 FROM draft_attachments WHERE blob_id = ?1)
             OR EXISTS (SELECT 1 FROM submission_attachments WHERE blob_id = ?1)
             OR EXISTS (SELECT 1 FROM sent_submission_attachments WHERE blob_id = ?1)
             OR EXISTS (SELECT 1 FROM appkit_sent_references WHERE blob_id = ?1)",
        [id.0.as_slice()],
        |row| row.get(0),
    )?;
    if !owned {
        match fs::remove_file(id.path(blobs)) {
            Ok(()) => sync_directory(blobs)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        transaction.execute(
            "DELETE FROM attachment_blobs WHERE id = ?1",
            [id.0.as_slice()],
        )?;
    }
    transaction.commit()?;
    Ok(())
}

fn attachment_root(database: &Path) -> PathBuf {
    let mut root = database.as_os_str().to_owned();
    root.push(".attachments");
    root.into()
}

fn create_owned_directory(path: &Path) -> io::Result<()> {
    fs::create_dir_all(path)?;
    if !fs::symlink_metadata(path)?.file_type().is_dir() {
        return Err(io::Error::other(
            "attachment directory is not a native directory",
        ));
    }
    Ok(())
}

fn clean_partial_files(staging: &Path) -> io::Result<()> {
    for entry in fs::read_dir(staging)? {
        let entry = entry?;
        if entry.file_type()?.is_file()
            && entry
                .file_name()
                .to_string_lossy()
                .starts_with(PARTIAL_PREFIX)
        {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}

fn recovery_candidates(
    database: &Connection,
    blobs: &Path,
) -> Result<BTreeSet<BlobId>, AttachmentError> {
    let mut statement = database.prepare(
        "SELECT b.id, NOT EXISTS (
           SELECT 1 FROM draft_attachments AS o WHERE o.blob_id = b.id
         ) AND NOT EXISTS (
           SELECT 1 FROM submission_attachments AS o WHERE o.blob_id = b.id
         ) AND NOT EXISTS (
           SELECT 1 FROM sent_submission_attachments AS o WHERE o.blob_id = b.id
         ) AND NOT EXISTS (
           SELECT 1 FROM appkit_sent_references AS o WHERE o.blob_id = b.id
         ) FROM attachment_blobs AS b",
    )?;
    let indexed = statement
        .query_map([], |row| Ok((BlobId(row.get(0)?), row.get::<_, bool>(1)?)))?
        .collect::<Result<HashMap<_, _>, _>>()?;
    let mut candidates: BTreeSet<_> = indexed
        .iter()
        .filter_map(|(id, orphaned)| orphaned.then_some(*id))
        .collect();

    for entry in fs::read_dir(blobs)? {
        let entry = entry?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        let mut id = [0; 32];
        if entry.file_type()?.is_file()
            && hex::decode_to_slice(name, &mut id).is_ok()
            && name == hex::encode(id)
        {
            let id = BlobId(id);
            if !indexed.contains_key(&id) {
                candidates.insert(id);
            }
        }
    }
    Ok(candidates)
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> io::Result<()> {
    File::open(path)?.sync_all()
}

#[cfg(not(unix))]
fn sync_directory(_path: &Path) -> io::Result<()> {
    Ok(())
}

pub(super) fn migrate(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE attachment_blobs (
            id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 32),
            size INTEGER NOT NULL CHECK (size >= 0)
        ) STRICT, WITHOUT ROWID;

        CREATE TABLE draft_attachments (
            draft_id BLOB NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
            blob_id BLOB NOT NULL REFERENCES attachment_blobs(id),
            PRIMARY KEY (draft_id, blob_id)
        ) STRICT, WITHOUT ROWID;
        CREATE INDEX draft_attachments_by_blob ON draft_attachments (blob_id);",
    )
}

#[cfg(test)]
mod tests;
