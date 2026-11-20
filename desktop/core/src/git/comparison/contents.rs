use super::*;
use crate::files::{FileError, read_local_file};

impl GitComparison {
    pub async fn file_contents(
        &self,
        id: ComparisonFileId,
        after: bool,
        limit: usize,
    ) -> Result<Option<Vec<u8>>, GitError> {
        let entry = self
            .entries
            .iter()
            .find(|entry| entry.id == id)
            .ok_or(GitError::RetiredFile)?;
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        self.verify_entry(entry).await?;
        let bytes = if after && self.target == ComparisonSide::WorkingTree {
            match entry
                .change
                .after
                .as_deref()
                .filter(|_| entry.change.blob(true).is_some())
            {
                Some(path) => match read_local_file(&self.owner.git.checkout, path, limit as u64) {
                    Ok(read) if Some(&read.revision) == entry.input.as_ref() => Some(read.bytes),
                    Ok(_) | Err(FileError::Changed | FileError::Replaced) => {
                        return Err(GitError::StaleComparison);
                    }
                    Err(FileError::TooLarge) => None,
                    Err(error) => return Err(error.into()),
                },
                None => None,
            }
        } else if let Some(oid) = entry.change.blob(after) {
            match self
                .owner
                .git
                .success(["--no-replace-objects", "cat-file", "blob", oid], limit)
                .await
            {
                Ok(bytes) => Some(bytes),
                Err(GitError::Limit) => None,
                Err(error) => return Err(error),
            }
        } else {
            None
        };
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        self.verify_entry(entry).await?;
        Ok(bytes)
    }
}
