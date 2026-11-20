use std::{
    ffi::OsStr,
    fs::{self, File, OpenOptions, TryLockError},
    io::{self, Read, Write},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize, de::DeserializeOwned};
use thiserror::Error;
use uuid::Uuid;

use crate::checkout::{CheckoutError, CheckoutIdentity, NativeFileIdentity};

const LOCK_NAME: &str = ".lock";
const AUTHORITY_NAME: &str = ".authority";
const DOCUMENT_VERSION: u32 = 1;
const MAX_DOCUMENT_BYTES: u64 = 64 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Edition {
    AppKit,
    Tauri,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum WorktreePhase {
    Preparing,
    Active,
    Removing,
    CheckoutRemoved,
    CreationCancelled,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeRecord {
    pub id: Uuid,
    #[serde(rename = "taskID")]
    pub task_id: String,
    #[serde(rename = "threadID", skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    pub source_project_path: PathBuf,
    pub repository_git_directory: PathBuf,
    pub branch: String,
    pub checkout_path: PathBuf,
    pub base_commit: String,
    pub source_was_dirty: bool,
    /// Seconds since 2001-01-01 UTC, as encoded by Foundation's default Date strategy.
    pub created_at: f64,
    pub phase: WorktreePhase,
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("another manager holds the worktree record lock")]
    Contended,
    #[error("the recorded {0:?} edition owns this worktree store")]
    Authority(Edition),
    #[error("the worktree record or authority document is invalid")]
    InvalidDocument,
    #[error("the worktree record has changed")]
    Changed,
    #[error("another workspace record owns this task, chat, branch or checkout")]
    Ownership,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct AuthorityDocument {
    version: u32,
    edition: Edition,
}

#[derive(Deserialize, Serialize)]
struct RecordDocument {
    version: u32,
    workspace: WorktreeRecord,
}

pub struct WorktreeStore {
    directory: CheckoutIdentity,
}

#[derive(Debug)]
pub struct WorktreeSnapshot {
    pub authority: Edition,
    pub records: Vec<WorktreeRecord>,
}

pub struct LockedWorktrees<'a> {
    store: &'a WorktreeStore,
    lock: File,
    authority: Edition,
}

impl WorktreeStore {
    /// Open an existing records directory, including one created by AppKit.
    pub fn open(records: &Path) -> Result<Self, StoreError> {
        Ok(Self {
            directory: CheckoutIdentity::capture(records)?,
        })
    }

    /// Initialize the records directory in a new Tauri-owned application profile.
    pub fn initialize_tauri(records: &Path) -> Result<Self, StoreError> {
        fs::create_dir_all(records)?;
        let store = Self::open(records)?;
        {
            let locked = store.acquire()?;
            if locked.authority != Edition::Tauri {
                for entry in fs::read_dir(store.path())? {
                    if entry?.file_name() != LOCK_NAME {
                        return Err(StoreError::Authority(locked.authority));
                    }
                }
                locked.persist(
                    Path::new(AUTHORITY_NAME),
                    &AuthorityDocument {
                        version: DOCUMENT_VERSION,
                        edition: Edition::Tauri,
                    },
                )?;
            }
        }
        Ok(store)
    }

    pub fn snapshot(&self) -> Result<WorktreeSnapshot, StoreError> {
        let locked = self.acquire()?;
        Ok(WorktreeSnapshot {
            authority: locked.authority,
            records: locked.list()?,
        })
    }

    pub fn lock_for(&self, edition: Edition) -> Result<LockedWorktrees<'_>, StoreError> {
        let locked = self.acquire()?;
        if locked.authority != edition {
            return Err(StoreError::Authority(locked.authority));
        }
        Ok(locked)
    }

    fn acquire(&self) -> Result<LockedWorktrees<'_>, StoreError> {
        self.directory.revalidate()?;
        let lock = open_regular(&self.path().join(LOCK_NAME), true)?;
        lock.try_lock().map_err(|error| match error {
            TryLockError::WouldBlock => StoreError::Contended,
            TryLockError::Error(error) => StoreError::Io(error),
        })?;
        let mut guard = LockedWorktrees {
            store: self,
            lock,
            authority: Edition::AppKit,
        };
        guard.revalidate()?;
        let document_path = self.path().join(AUTHORITY_NAME);
        if let Some(document) = read_optional::<AuthorityDocument>(&document_path)? {
            if document.version != DOCUMENT_VERSION {
                return Err(StoreError::InvalidDocument);
            }
            guard.authority = document.edition;
        }
        Ok(guard)
    }

    fn path(&self) -> &Path {
        self.directory.canonical_path()
    }
}

impl LockedWorktrees<'_> {
    pub fn list(&self) -> Result<Vec<WorktreeRecord>, StoreError> {
        self.revalidate()?;
        let mut records = Vec::new();
        for entry in fs::read_dir(self.store.path())? {
            let path = entry?.path();
            if path.extension() == Some(OsStr::new("json")) {
                let document = read_required::<RecordDocument>(&path)?;
                records.push(validate_document(&path, document)?);
            }
        }
        records.sort_by(|a, b| a.created_at.total_cmp(&b.created_at).then(a.id.cmp(&b.id)));
        self.revalidate()?;
        Ok(records)
    }

    pub fn load(&self, id: Uuid) -> Result<Option<WorktreeRecord>, StoreError> {
        self.revalidate()?;
        let path = self.store.path().join(record_name(id));
        let record = read_optional::<RecordDocument>(&path)?
            .map(|document| validate_document(&path, document))
            .transpose()?;
        self.revalidate()?;
        Ok(record)
    }

    /// Compare against the complete record captured by the caller before changing its phase.
    pub fn save(
        &self,
        expected: Option<&WorktreeRecord>,
        record: &WorktreeRecord,
    ) -> Result<(), StoreError> {
        record.validate()?;
        let records = self.list()?;
        let current = records.iter().find(|current| current.id == record.id);
        if current != expected {
            return Err(StoreError::Changed);
        }
        if current.is_some_and(|current| !current.can_update_to(record))
            || records.iter().any(|other| {
                other.id != record.id
                    && (other.task_id == record.task_id
                        || other.checkout_path == record.checkout_path
                        || (other.repository_git_directory == record.repository_git_directory
                            && other.branch == record.branch)
                        || (other.thread_id.is_some() && other.thread_id == record.thread_id))
            })
        {
            return Err(StoreError::Ownership);
        }
        self.persist(
            Path::new(&record_name(record.id)),
            &RecordDocument {
                version: DOCUMENT_VERSION,
                workspace: record.clone(),
            },
        )
    }

    fn persist(&self, name: &Path, document: &impl Serialize) -> Result<(), StoreError> {
        let bytes = serde_json::to_vec(document)?;
        if bytes.len() as u64 > MAX_DOCUMENT_BYTES {
            return Err(StoreError::InvalidDocument);
        }
        let mut staged = tempfile::NamedTempFile::new_in(self.store.path())?;
        staged.write_all(&bytes)?;
        staged.as_file().sync_all()?;
        self.revalidate()?;
        staged
            .persist(self.store.path().join(name))
            .map_err(|error| error.error)?;
        #[cfg(unix)]
        self.store.directory.directory().sync_all()?;
        Ok(())
    }

    fn revalidate(&self) -> Result<(), StoreError> {
        self.store.directory.revalidate()?;
        let live_lock = open_regular(&self.store.path().join(LOCK_NAME), false)?;
        if NativeFileIdentity::from_file(&live_lock, &live_lock.metadata()?)?
            != NativeFileIdentity::from_file(&self.lock, &self.lock.metadata()?)?
        {
            return Err(StoreError::InvalidDocument);
        }
        Ok(())
    }
}

impl WorktreeRecord {
    fn validate(&self) -> Result<(), StoreError> {
        if self.id.is_nil()
            || self.task_id.trim().is_empty()
            || self
                .thread_id
                .as_ref()
                .is_some_and(|id| id.trim().is_empty())
            || !self.source_project_path.is_absolute()
            || !self.repository_git_directory.is_absolute()
            || !self.checkout_path.is_absolute()
            || self.branch.is_empty()
            || !matches!(self.base_commit.len(), 40 | 64)
            || !self
                .base_commit
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit())
            || !self.created_at.is_finite()
        {
            return Err(StoreError::InvalidDocument);
        }
        Ok(())
    }

    fn can_update_to(&self, next: &Self) -> bool {
        let mut candidate = self.clone();
        candidate.phase = next.phase;
        if self.thread_id.is_none() {
            candidate.thread_id = next.thread_id.clone();
        }
        &candidate == next
    }
}

fn validate_document(path: &Path, document: RecordDocument) -> Result<WorktreeRecord, StoreError> {
    let workspace = document.workspace;
    workspace.validate()?;
    if document.version != DOCUMENT_VERSION
        || path.file_name() != Some(OsStr::new(&record_name(workspace.id)))
    {
        return Err(StoreError::InvalidDocument);
    }
    Ok(workspace)
}

fn record_name(id: Uuid) -> String {
    format!("{id}.json")
}

fn read_optional<T: DeserializeOwned>(path: &Path) -> Result<Option<T>, StoreError> {
    match read_required(path) {
        Ok(document) => Ok(Some(document)),
        Err(StoreError::Io(error)) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn read_required<T: DeserializeOwned>(path: &Path) -> Result<T, StoreError> {
    let mut bytes = Vec::new();
    open_regular(path, false)?
        .take(MAX_DOCUMENT_BYTES + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_DOCUMENT_BYTES {
        return Err(StoreError::InvalidDocument);
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn open_regular(path: &Path, lock: bool) -> Result<File, StoreError> {
    let mut options = OpenOptions::new();
    options.read(true).write(lock).create(lock);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_FLAG_OPEN_REPARSE_POINT;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    let file = options.open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(StoreError::InvalidDocument);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;
        if metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            return Err(StoreError::InvalidDocument);
        }
    }
    Ok(file)
}

#[cfg(test)]
mod tests;
