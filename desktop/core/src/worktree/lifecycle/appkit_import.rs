use super::*;

impl WorktreeManager {
    /// Capture the existing registration and native identities without changing Git or worktree files.
    pub async fn capture_appkit_record(
        &self,
        mut record: WorktreeRecord,
    ) -> Result<WorktreeRecord, WorktreeError> {
        let (source, repository) = self.recorded_source(&record).await?;
        let registered = registered_paths(&source)
            .await?
            .contains(&record.checkout_path);
        let checkout = match fs::symlink_metadata(&record.checkout_path) {
            Ok(metadata) if metadata.is_dir() => {
                Some(CheckoutIdentity::capture(&record.checkout_path)?)
            }
            Ok(_) => return Err(WorktreeError::Ownership),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(error.into()),
        };
        match record.phase {
            WorktreePhase::Active if !registered || checkout.is_none() => {
                return Err(WorktreeError::Ownership);
            }
            WorktreePhase::CheckoutRemoved | WorktreePhase::CreationCancelled
                if registered || checkout.is_some() =>
            {
                return Err(WorktreeError::Ownership);
            }
            _ => {}
        }
        if let Some(checkout) = checkout {
            if checkout.canonical_path() != record.checkout_path
                || record
                    .checkout_identity
                    .as_ref()
                    .is_some_and(|identity| identity != &checkout.storage_key())
            {
                return Err(WorktreeError::Ownership);
            }
            if registered {
                self.verify_registered(&record, &repository).await?;
            } else if record.phase != WorktreePhase::Preparing
                || fs::read_dir(&record.checkout_path)?.next().is_some()
            {
                return Err(WorktreeError::Ownership);
            }
            record.checkout_identity = Some(checkout.storage_key());
        }
        repository.revalidate()?;
        record.repository_identity = Some(repository.storage_key());
        Ok(record)
    }
}
