use std::os::unix::fs::symlink;

use super::*;

impl WorktreeStore {
    /// Verify the original AppKit lock remains retired for this specific transfer.
    pub fn retired_appkit(&self, transfer: Uuid) -> Result<bool, StoreError> {
        self.directory.revalidate()?;
        let lock = self.path().join(LOCK_NAME);
        let retired = match fs::symlink_metadata(&lock) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                fs::read_link(lock)? == retirement_marker(transfer)
            }
            Ok(metadata) if metadata.is_file() => false,
            Ok(_) => return Err(StoreError::InvalidDocument),
            Err(error) if error.kind() == io::ErrorKind::NotFound => false,
            Err(error) => return Err(error.into()),
        };
        self.directory.revalidate()?;
        Ok(retired && !transfer.is_nil())
    }
}

impl LockedWorktrees<'_> {
    /// Commit retirement under the live AppKit lock after the installer checks quiescence.
    /// Pinned AppKit opens this path with O_NOFOLLOW before each managed checkout operation.
    pub fn retire_appkit(&self, transfer: Uuid) -> Result<(), StoreError> {
        if self.authority != Edition::AppKit {
            return Err(StoreError::Authority(self.authority));
        }
        if transfer.is_nil() {
            return Err(StoreError::InvalidDocument);
        }
        let temporary = tempfile::tempdir_in(self.store.path())?;
        let guard = temporary.path().join(LOCK_NAME);
        symlink(retirement_marker(transfer), &guard)?;
        self.revalidate()?;
        fs::rename(&guard, self.store.path().join(LOCK_NAME))?;
        self.store.directory.directory().sync_all()?;
        Ok(())
    }
}

fn retirement_marker(transfer: Uuid) -> PathBuf {
    PathBuf::from(".retired-by-tauri").join(transfer.to_string())
}
