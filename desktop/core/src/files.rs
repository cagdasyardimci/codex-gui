use std::{
    collections::HashMap,
    fs::{self, File, Metadata},
    io::{self, Read},
    path::{Component, Path, PathBuf},
    time::SystemTime,
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;
use ts_rs::TS;
use uuid::Uuid;

use crate::checkout::{CheckoutError, CheckoutIdentity, NativeFileIdentity};

pub mod index;
mod native;
mod save;
pub mod search;
pub use save::MAX_EDIT_BYTES;

pub const MAX_READ_BYTES: u64 = 32 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize, TS)]
pub struct FileHandle(Uuid);

#[derive(Clone, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct FileLink {
    pub id: FileHandle,
    pub display_path: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileRevision {
    pub digest: String,
    pub byte_count: usize,
}

#[derive(Debug)]
pub struct FileRead {
    pub bytes: Vec<u8>,
    pub revision: FileRevision,
}

#[derive(Debug, Error)]
pub enum FileError {
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error("file path must identify a regular file within the checkout")]
    InvalidPath,
    #[error("file handle does not belong to this checkout scope")]
    InvalidHandle,
    #[error("file identity changed at its captured path")]
    Replaced,
    #[error("file changed during the read")]
    Changed,
    #[error("file exceeds the bounded read limit")]
    TooLarge,
    #[error("file permissions disallow editing")]
    ReadOnly,
    #[error("file contents are not UTF-8 text")]
    UnsupportedEncoding,
    #[error(transparent)]
    Io(#[from] io::Error),
}

pub struct CheckoutFiles {
    checkout: CheckoutIdentity,
    files: HashMap<FileHandle, CapturedFile>,
}

struct CapturedFile {
    relative: PathBuf,
    identity: NativeFileIdentity,
    // Keeping the originally opened file alive prevents reuse of its native identity.
    _anchor: File,
}

impl CheckoutFiles {
    pub fn new(checkout: CheckoutIdentity) -> Self {
        Self {
            checkout,
            files: HashMap::new(),
        }
    }

    pub fn issue(&mut self, relative: &Path) -> Result<FileLink, FileError> {
        let file = CapturedFile::capture(&self.checkout, relative)?;
        let id = FileHandle(Uuid::new_v4());
        self.files.insert(id, file);
        Ok(FileLink {
            id,
            display_path: relative.to_string_lossy().into_owned(),
        })
    }

    pub fn read(&self, handle: FileHandle) -> Result<FileRead, FileError> {
        self.read_limited(handle, MAX_READ_BYTES)
    }

    pub fn read_limited(&self, handle: FileHandle, limit: u64) -> Result<FileRead, FileError> {
        let file = self.files.get(&handle).ok_or(FileError::InvalidHandle)?;
        file.read(&self.checkout, limit.min(MAX_READ_BYTES))
    }

    pub fn close(&mut self, handle: FileHandle) {
        self.files.remove(&handle);
    }

    pub fn validate(&self, handle: FileHandle) -> Result<(), FileError> {
        self.files
            .get(&handle)
            .ok_or(FileError::InvalidHandle)?
            .reopen(&self.checkout)?;
        self.checkout.revalidate()?;
        Ok(())
    }

    pub fn same_file(&self, handle: FileHandle, other: &Self, other_handle: FileHandle) -> bool {
        let pair = self.files.get(&handle).zip(other.files.get(&other_handle));
        self.checkout == other.checkout
            && pair.is_some_and(|(first, second)| {
                first.identity == second.identity && first.relative == second.relative
            })
    }

    pub fn duplicate(&self, handle: FileHandle) -> Result<Self, FileError> {
        let captured = self.files.get(&handle).ok_or(FileError::InvalidHandle)?;
        let copy = CapturedFile {
            relative: captured.relative.clone(),
            identity: captured.identity.clone(),
            _anchor: captured._anchor.try_clone()?,
        };
        Ok(Self {
            checkout: self.checkout.clone(),
            files: HashMap::from([(handle, copy)]),
        })
    }
}

impl CapturedFile {
    fn capture(checkout: &CheckoutIdentity, relative: &Path) -> Result<Self, FileError> {
        let file = open_regular(checkout, relative)?;
        let identity = NativeFileIdentity::from_file(&file, &file.metadata()?)?;
        checkout.revalidate()?;
        Ok(Self {
            relative: relative.to_path_buf(),
            identity,
            _anchor: file,
        })
    }

    fn read(&self, checkout: &CheckoutIdentity, limit: u64) -> Result<FileRead, FileError> {
        let opened = self.reopen(checkout)?;
        let read = read_bounded(&opened, limit)?;
        // Confirm the still-published name after reading from its open descriptor.
        self.reopen(checkout)?;
        checkout.revalidate()?;
        Ok(read)
    }

    fn reopen(&self, checkout: &CheckoutIdentity) -> Result<File, FileError> {
        let file = open_regular(checkout, &self.relative)?;
        self.verify_identity(&file)?;
        Ok(file)
    }

    fn verify_identity(&self, file: &File) -> Result<Metadata, FileError> {
        let metadata = file.metadata()?;
        if !metadata.is_file() || NativeFileIdentity::from_file(file, &metadata)? != self.identity {
            return Err(FileError::Replaced);
        }
        Ok(metadata)
    }
}

pub(crate) fn comparison_file_revision(
    checkout: &CheckoutIdentity,
    relative: &Path,
    limit: u64,
) -> Result<FileRevision, FileError> {
    checkout.revalidate()?;
    let components = path_components(relative)?;
    let (_, directories) = components.split_last().ok_or(FileError::InvalidPath)?;
    let path = checkout.canonical_path().join(relative);
    if fs::symlink_metadata(&path)?.file_type().is_symlink() {
        let root = checkout.directory();
        let parent = native::open_parent(root, directories)?;
        let parent = parent.as_ref().unwrap_or(root);
        let parent_id = NativeFileIdentity::from_file(parent, &parent.metadata()?)?;
        let link = fs::read_link(&path)?;
        let recheck = native::open_parent(root, directories)?;
        let recheck = recheck.as_ref().unwrap_or(root);
        if parent_id != NativeFileIdentity::from_file(recheck, &recheck.metadata()?)?
            || fs::read_link(&path)? != link
        {
            return Err(FileError::Changed);
        }
        checkout.revalidate()?;
        let bytes = link.as_os_str().as_encoded_bytes();
        if bytes.len() as u64 > limit {
            return Err(FileError::TooLarge);
        }
        return Ok(FileRevision::from_bytes(bytes));
    }
    Ok(CapturedFile::capture(checkout, relative)?
        .read(checkout, limit)?
        .revision)
}

pub fn local_file_revision(
    checkout: &CheckoutIdentity,
    relative: &Path,
    limit: u64,
) -> Result<FileRevision, FileError> {
    Ok(read_local_file(checkout, relative, limit)?.revision)
}

pub fn validate_local_file(checkout: &CheckoutIdentity, relative: &Path) -> Result<(), FileError> {
    CapturedFile::capture(checkout, relative)?.reopen(checkout)?;
    Ok(())
}

pub fn read_local_file(
    checkout: &CheckoutIdentity,
    relative: &Path,
    limit: u64,
) -> Result<FileRead, FileError> {
    CapturedFile::capture(checkout, relative)?.read(checkout, limit.min(MAX_READ_BYTES))
}

fn open_regular(checkout: &CheckoutIdentity, relative: &Path) -> Result<File, FileError> {
    checkout.revalidate()?;
    let components = path_components(relative)?;
    let (name, directories) = components.split_last().ok_or(FileError::InvalidPath)?;
    let root = checkout.directory();
    let parent = native::open_parent(root, directories)?;
    let file = native::open_read(parent.as_ref().unwrap_or(root), name)?;
    if !file.metadata()?.is_file() {
        return Err(FileError::InvalidPath);
    }
    Ok(file)
}

fn path_components(relative: &Path) -> Result<Vec<&std::ffi::OsStr>, FileError> {
    relative
        .components()
        .map(|component| match component {
            Component::Normal(name) => Ok(name),
            _ => Err(FileError::InvalidPath),
        })
        .collect()
}

fn read_bounded(mut file: &File, limit: u64) -> Result<FileRead, FileError> {
    let before = file.metadata()?;
    if before.len() > limit {
        return Err(FileError::TooLarge);
    }
    let mut bytes = Vec::new();
    file.by_ref().take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(FileError::TooLarge);
    }
    let after = file.metadata()?;
    if after.len() != bytes.len() as u64 || fingerprint(&before) != fingerprint(&after) {
        return Err(FileError::Changed);
    }
    Ok(FileRead {
        revision: FileRevision::from_bytes(&bytes),
        bytes,
    })
}

impl FileRevision {
    pub(crate) fn from_bytes(bytes: &[u8]) -> Self {
        Self {
            digest: hex::encode(Sha256::digest(bytes)),
            byte_count: bytes.len(),
        }
    }
}

fn fingerprint(metadata: &Metadata) -> (u64, Option<SystemTime>) {
    (metadata.len(), metadata.modified().ok())
}

#[cfg(test)]
mod tests;
