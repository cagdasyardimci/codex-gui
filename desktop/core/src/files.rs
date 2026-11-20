use std::{
    collections::HashMap,
    fs::{File, Metadata},
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

mod native;

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
        let file = open_regular(&self.checkout, relative)?;
        let identity = NativeFileIdentity::from_file(&file, &file.metadata()?)?;
        self.checkout.revalidate()?;
        let id = FileHandle(Uuid::new_v4());
        self.files.insert(
            id,
            CapturedFile {
                relative: relative.to_path_buf(),
                identity,
                _anchor: file,
            },
        );
        Ok(FileLink {
            id,
            display_path: relative.to_string_lossy().into_owned(),
        })
    }

    pub fn read(&self, handle: FileHandle) -> Result<FileRead, FileError> {
        let file = self.files.get(&handle).ok_or(FileError::InvalidHandle)?;
        let opened = file.reopen(&self.checkout)?;
        let read = read_bounded(&opened, MAX_READ_BYTES)?;
        // Confirm the still-published name after reading from its open descriptor.
        file.reopen(&self.checkout)?;
        self.checkout.revalidate()?;
        Ok(read)
    }

    pub fn close(&mut self, handle: FileHandle) {
        self.files.remove(&handle);
    }
}

impl CapturedFile {
    fn reopen(&self, checkout: &CheckoutIdentity) -> Result<File, FileError> {
        let file = open_regular(checkout, &self.relative)?;
        if NativeFileIdentity::from_file(&file, &file.metadata()?)? != self.identity {
            return Err(FileError::Replaced);
        }
        Ok(file)
    }
}

fn open_regular(checkout: &CheckoutIdentity, relative: &Path) -> Result<File, FileError> {
    checkout.revalidate()?;
    let components: Vec<_> = relative
        .components()
        .map(|component| match component {
            Component::Normal(name) => Ok(name),
            _ => Err(FileError::InvalidPath),
        })
        .collect::<Result<_, _>>()?;
    if components.is_empty() {
        return Err(FileError::InvalidPath);
    }
    let file = native::open_contained(checkout.directory(), &components)?;
    if !file.metadata()?.is_file() {
        return Err(FileError::InvalidPath);
    }
    Ok(file)
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
        revision: FileRevision {
            digest: hex::encode(Sha256::digest(&bytes)),
            byte_count: bytes.len(),
        },
        bytes,
    })
}

fn fingerprint(metadata: &Metadata) -> (u64, Option<SystemTime>) {
    (metadata.len(), metadata.modified().ok())
}

#[cfg(test)]
mod tests;
