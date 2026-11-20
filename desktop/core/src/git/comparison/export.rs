use crate::files::{MAX_READ_BYTES, comparison_file_revision};

use super::*;

const MAX_INPUT_BYTES: u64 = 64 * 1024 * 1024;

impl GitComparison {
    pub async fn export_patch(&self) -> Result<Vec<u8>, GitError> {
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        if let Some(bytes) = self
            .shared
            .as_ref()
            .and_then(|shared| shared.get_patch(None))
        {
            return Ok(bytes.to_vec());
        }
        if self.is_mutable() {
            self.verify_snapshot().await?;
        }
        let patch = self
            .diff(PATCH_ARGUMENTS, std::iter::empty(), COMPARISON_PATCH_BYTES)
            .await?;
        if self.is_mutable() {
            let repeated = self
                .diff(PATCH_ARGUMENTS, std::iter::empty(), COMPARISON_PATCH_BYTES)
                .await?;
            if repeated != patch {
                return Err(GitError::StaleComparison);
            }
            self.verify_snapshot().await?;
        }
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        if let Some(shared) = &self.shared {
            shared.store_patch(None, &patch);
        }
        Ok(patch)
    }

    pub(super) async fn capture_entries(&self) -> Result<Vec<Entry>, GitError> {
        let mut remaining = MAX_INPUT_BYTES;
        let mut entries = Vec::new();
        for change in self.read_summary().await? {
            let input = self.capture_input(&change, remaining).await?;
            if let Some(input) = &input {
                remaining -= input.byte_count as u64;
            }
            entries.push(Entry {
                id: ComparisonFileId(Uuid::new_v4()),
                change,
                input,
            });
        }
        Ok(entries)
    }

    pub(super) async fn verify_entry(&self, entry: &Entry) -> Result<(), GitError> {
        if self.is_mutable() && self.owner.diff_policy().await? != self.policy {
            return Err(GitError::StaleComparison);
        }
        self.verify_input(entry, MAX_READ_BYTES).await?;
        Ok(())
    }

    pub(super) fn is_mutable(&self) -> bool {
        !matches!(self.target, ComparisonSide::Object(_))
    }

    async fn verify_snapshot(&self) -> Result<(), GitError> {
        if self.owner.diff_policy().await? != self.policy {
            return Err(GitError::StaleComparison);
        }
        self.verify_summary().await?;
        let mut remaining = MAX_INPUT_BYTES;
        for entry in self.entries.iter() {
            remaining -= self.verify_input(entry, remaining).await?;
        }
        Ok(())
    }

    pub(super) async fn verify_summary(&self) -> Result<(), GitError> {
        let revisions = self.read_summary().await?;
        if !revisions
            .iter()
            .eq(self.entries.iter().map(|entry| &entry.change))
        {
            return Err(GitError::StaleComparison);
        }
        Ok(())
    }

    async fn verify_input(&self, entry: &Entry, available: u64) -> Result<u64, GitError> {
        let current = self
            .capture_input(&entry.change, available)
            .await
            .map_err(|error| match error {
                GitError::File(_) | GitError::Limit => GitError::StaleComparison,
                error => error,
            })?;
        if current != entry.input {
            return Err(GitError::StaleComparison);
        }
        Ok(current.map_or(0, |stamp| stamp.byte_count as u64))
    }

    async fn capture_input(
        &self,
        change: &RawChange,
        available: u64,
    ) -> Result<Option<FileRevision>, GitError> {
        let path = match (&self.target, &change.after) {
            (ComparisonSide::WorkingTree, Some(path)) => path,
            _ => return Ok(None),
        };
        let checkout = &self.owner.git.checkout;
        let revision = if change.is_gitlink() {
            gitlink_revision(checkout, path).await?
        } else {
            comparison_file_revision(checkout, path, available.min(MAX_READ_BYTES))?
        };
        if revision.byte_count as u64 > available {
            return Err(GitError::Limit);
        }
        Ok(Some(revision))
    }
}

async fn gitlink_revision(
    checkout: &CheckoutIdentity,
    relative: &Path,
) -> Result<FileRevision, GitError> {
    let path = checkout.canonical_path().join(relative);
    let nested = CheckoutIdentity::capture(&path)?;
    if nested.canonical_path() != path {
        return Err(GitError::RetiredFile);
    }
    let nested = GitComparisons::open(nested).await?;
    let mut content = nested.resolve_commit("HEAD").await?.into_bytes();
    let policy = nested.diff_policy().await?;
    let status = nested
        .git
        .success(
            policy.iter().map(OsString::as_os_str).chain(
                [
                    "status",
                    "--porcelain=v1",
                    "-z",
                    "--untracked-files=all",
                    "--ignore-submodules=none",
                ]
                .into_iter()
                .map(OsStr::new),
            ),
            QUERY_BYTES,
        )
        .await?;
    content.extend_from_slice(&status);
    nested.verify_repository().await?;
    Ok(FileRevision::from_bytes(&content))
}
