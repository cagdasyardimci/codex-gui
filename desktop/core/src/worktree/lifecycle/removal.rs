use crate::workspace::CleanupReservation;

use super::*;

impl WorktreeManager {
    pub async fn remove_clean(
        &self,
        id: Uuid,
        reservation: CleanupReservation,
    ) -> Result<WorktreeRecord, WorktreeError> {
        let locked = self.store.lock_for(Edition::Tauri)?;
        let active = locked.load(id)?.ok_or(WorktreeError::Unknown)?;
        if active.phase != WorktreePhase::Active {
            return Err(WorktreeError::Inactive);
        }
        if active.checkout_path != reservation.checkout().canonical_path() {
            return Err(WorktreeError::Ownership);
        }
        reservation.revalidate()?;
        let (source, repository) = self.recorded_source(&active).await?;
        if !registered_paths(&source)
            .await?
            .contains(&active.checkout_path)
        {
            return Err(WorktreeError::Ownership);
        }
        let target = self.verify_registered(&active, &repository).await?;
        if &target.checkout != reservation.checkout() {
            return Err(WorktreeError::Ownership);
        }
        verify_clean(&target).await?;
        let mut removing = active.clone();
        removing.phase = WorktreePhase::Removing;
        locked.save(Some(&active), &removing)?;

        repository.revalidate()?;
        self.checkouts.revalidate()?;
        reservation.revalidate()?;
        verify_branch(&target, &removing.branch).await?;
        let path = git_path(&removing.checkout_path);
        source
            .success(
                [
                    OsStr::new("worktree"),
                    OsStr::new("remove"),
                    OsStr::new("--"),
                    path.as_os_str(),
                ],
                GIT_RESPONSE_BYTES,
            )
            .await?;
        match removing.checkout_path.symlink_metadata() {
            Ok(_) => return Err(WorktreeError::Ownership),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        if registered_paths(&source)
            .await?
            .contains(&removing.checkout_path)
        {
            return Err(WorktreeError::Ownership);
        }
        let mut removed = removing.clone();
        removed.phase = WorktreePhase::CheckoutRemoved;
        locked.save(Some(&removing), &removed)?;
        Ok(removed)
    }
}

async fn verify_clean(target: &CheckoutGit) -> Result<(), WorktreeError> {
    let args = [
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
        "--ignored=matching",
        "--ignore-submodules=none",
    ];
    match target.success(args, GIT_RESPONSE_BYTES).await {
        Ok(output) if output.is_empty() => Ok(()),
        Ok(_) | Err(GitError::Limit) => Err(WorktreeError::Dirty),
        Err(error) => Err(error.into()),
    }
}
