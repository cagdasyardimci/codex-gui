use super::*;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecoveryKind {
    Active,
    CreationInterrupted,
    RemovalInterrupted,
    MissingCheckout,
    OwnershipConflict,
    CheckoutRemoved,
    CreationCancelled,
}

#[derive(Debug, PartialEq)]
pub struct WorktreeRecovery {
    pub record: WorktreeRecord,
    pub kind: RecoveryKind,
}

impl WorktreeManager {
    pub async fn recover(&self) -> Result<Vec<WorktreeRecovery>, WorktreeError> {
        let locked = self.store.lock_for(Edition::Tauri)?;
        let mut results = Vec::new();
        for mut record in locked.list()? {
            let (kind, next) = self
                .recovery_outcome(&record)
                .await
                .unwrap_or((RecoveryKind::OwnershipConflict, record.phase));
            if next != record.phase {
                let previous = record.clone();
                record.phase = next;
                locked.save(Some(&previous), &record)?;
            }
            results.push(WorktreeRecovery { record, kind });
        }
        Ok(results)
    }

    async fn recovery_outcome(
        &self,
        record: &WorktreeRecord,
    ) -> Result<(RecoveryKind, WorktreePhase), WorktreeError> {
        use {RecoveryKind as Kind, WorktreePhase as Phase};

        let (source, repository) = self.recorded_source(record).await?;
        let registered = registered_paths(&source)
            .await?
            .contains(&record.checkout_path);
        let present = match record.checkout_path.symlink_metadata() {
            Ok(_) => true,
            Err(error) if error.kind() == io::ErrorKind::NotFound => false,
            Err(error) => return Err(error.into()),
        };
        let unchanged = |kind| Ok((kind, record.phase));
        match (record.phase, present, registered) {
            (Phase::Preparing, false, false) => unchanged(Kind::CreationInterrupted),
            (Phase::Preparing, true, false) if vacant_preparation(record)? => {
                unchanged(Kind::CreationInterrupted)
            }
            (Phase::Active, false, _) => unchanged(Kind::MissingCheckout),
            (Phase::Removing, false, false) => Ok((Kind::CheckoutRemoved, Phase::CheckoutRemoved)),
            (Phase::CheckoutRemoved, false, false) => unchanged(Kind::CheckoutRemoved),
            (Phase::CreationCancelled, false, false) => unchanged(Kind::CreationCancelled),
            (Phase::Preparing, true, true) if record.checkout_identity.is_some() => {
                let checkout = self.verify_registered(record, &repository).await?;
                if head(&checkout).await? == record.base_commit {
                    Ok((Kind::Active, Phase::Active))
                } else {
                    unchanged(Kind::OwnershipConflict)
                }
            }
            (Phase::Active, true, true) => {
                self.verify_registered(record, &repository).await?;
                unchanged(Kind::Active)
            }
            (Phase::Removing, true, true) => {
                self.verify_registered(record, &repository).await?;
                Ok((Kind::RemovalInterrupted, Phase::Active))
            }
            _ => unchanged(Kind::OwnershipConflict),
        }
    }
}

fn vacant_preparation(record: &WorktreeRecord) -> Result<bool, WorktreeError> {
    let Some(expected) = &record.checkout_identity else {
        return Ok(false);
    };
    let current = CheckoutIdentity::capture(&record.checkout_path)?;
    Ok(current.canonical_path() == record.checkout_path
        && &current.storage_key() == expected
        && fs::read_dir(current.canonical_path())?
            .next()
            .transpose()?
            .is_none())
}
