use std::{
    fs::{self, File, Metadata, OpenOptions},
    hash::{Hash, Hasher},
    io,
    path::{Path, PathBuf},
    sync::Arc,
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum CheckoutError {
    #[error("checkout path must be absolute: {0}")]
    Relative(PathBuf),
    #[error("could not identify checkout {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("reported checkout {reported} belongs outside {expected}")]
    Mismatch {
        expected: PathBuf,
        reported: PathBuf,
    },
    #[error("checkout was replaced at {0}")]
    Replaced(PathBuf),
}

#[derive(Clone, Debug)]
pub struct CheckoutIdentity {
    canonical: PathBuf,
    key: NativeFileIdentity,
    // A live reference prevents the old directory's identity from being reused.
    directory: Arc<File>,
}

impl CheckoutIdentity {
    pub fn capture(path: &Path) -> Result<Self, CheckoutError> {
        let canonical = canonicalize(path)?;
        let (directory, key) = identify_directory(&canonical)?;
        Ok(Self {
            canonical,
            key,
            directory: Arc::new(directory),
        })
    }

    pub fn canonical_path(&self) -> &Path {
        &self.canonical
    }

    pub(crate) fn directory(&self) -> &File {
        &self.directory
    }

    #[cfg(windows)]
    pub(crate) fn reopen_directory(&self) -> Result<File, CheckoutError> {
        let (directory, key) = identify_directory(&self.canonical)?;
        if key != self.key {
            return Err(CheckoutError::Replaced(self.canonical.clone()));
        }
        Ok(directory)
    }

    pub(crate) fn storage_key(&self) -> String {
        #[cfg(unix)]
        return format!(
            "{}:{}:{}",
            std::env::consts::OS,
            self.key.device,
            self.key.inode
        );
        #[cfg(windows)]
        return format!("windows:{}:{}", self.key.volume, hex::encode(self.key.id));
    }

    pub fn revalidate(&self) -> Result<(), CheckoutError> {
        self.validate_reported(&self.canonical)
    }

    pub fn validate_reported(&self, path: &Path) -> Result<(), CheckoutError> {
        let reported = canonicalize(path)?;
        if reported != self.canonical {
            return Err(CheckoutError::Mismatch {
                expected: self.canonical.clone(),
                reported,
            });
        }
        let (_, key) = identify_directory(&reported)?;
        if self.key != key {
            return Err(CheckoutError::Replaced(reported));
        }
        Ok(())
    }
}

impl PartialEq for CheckoutIdentity {
    fn eq(&self, other: &Self) -> bool {
        self.canonical == other.canonical && self.key == other.key
    }
}

impl Eq for CheckoutIdentity {}

impl Hash for CheckoutIdentity {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.canonical.hash(state);
        self.key.hash(state);
    }
}

fn canonicalize(path: &Path) -> Result<PathBuf, CheckoutError> {
    if !path.is_absolute() {
        return Err(CheckoutError::Relative(path.to_path_buf()));
    }
    fs::canonicalize(path).map_err(|source| CheckoutError::Io {
        path: path.to_path_buf(),
        source,
    })
}

fn identify_directory(path: &Path) -> Result<(File, NativeFileIdentity), CheckoutError> {
    let read = || {
        let file = open_directory(path)?;
        let metadata = file.metadata()?;
        if !metadata.is_dir() {
            return Err(io::ErrorKind::NotADirectory.into());
        }
        let key = NativeFileIdentity::from_file(&file, &metadata)?;
        Ok((file, key))
    };
    read().map_err(|source| CheckoutError::Io {
        path: path.to_path_buf(),
        source,
    })
}

#[cfg(unix)]
fn open_directory(path: &Path) -> io::Result<File> {
    use std::os::unix::fs::OpenOptionsExt;

    OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY)
        .open(path)
}

#[cfg(unix)]
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(crate) struct NativeFileIdentity {
    device: u64,
    inode: u64,
}

#[cfg(unix)]
impl NativeFileIdentity {
    pub(crate) fn from_file(_file: &File, metadata: &Metadata) -> io::Result<Self> {
        use std::os::unix::fs::MetadataExt;

        Ok(Self {
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
}

#[cfg(windows)]
fn open_directory(path: &Path) -> io::Result<File> {
    use std::os::windows::fs::OpenOptionsExt;
    use windows_sys::Win32::Storage::FileSystem::FILE_FLAG_BACKUP_SEMANTICS;

    OpenOptions::new()
        .read(true)
        .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)
}

#[cfg(windows)]
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(crate) struct NativeFileIdentity {
    volume: u64,
    id: [u8; 16],
}

#[cfg(windows)]
impl NativeFileIdentity {
    pub(crate) fn from_file(file: &File, _metadata: &Metadata) -> io::Result<Self> {
        use std::{mem::MaybeUninit, os::windows::io::AsRawHandle};
        use windows_sys::Win32::Storage::FileSystem::{
            FILE_ID_INFO, FileIdInfo, GetFileInformationByHandleEx,
        };

        let mut result = MaybeUninit::<FILE_ID_INFO>::uninit();
        // The borrowed file keeps the handle alive. The buffer has the layout for FileIdInfo.
        let success = unsafe {
            GetFileInformationByHandleEx(
                file.as_raw_handle(),
                FileIdInfo,
                result.as_mut_ptr().cast(),
                size_of::<FILE_ID_INFO>() as u32,
            )
        };
        if success == 0 {
            return Err(io::Error::last_os_error());
        }
        // A successful call initialized the complete FILE_ID_INFO value.
        let result = unsafe { result.assume_init() };
        Ok(Self {
            volume: result.VolumeSerialNumber,
            id: result.FileId.Identifier,
        })
    }
}

#[cfg(test)]
mod tests;
