use std::{fs, io, path::PathBuf};

use codex_gui_core::{
    checkout::{CheckoutError, CheckoutIdentity},
    identity::ThreadId,
    ipc::WriteAccess,
    workspace::WorktreeThreadBinding,
    worktree::{Edition, WorktreeManager, WorktreePhase, WorktreeStore},
};
use uuid::Uuid;

use super::{Failure, Navigation};

impl Navigation {
    pub(super) async fn create_managed_worktree(&mut self) -> Result<(), Failure> {
        if self.view.write_access != WriteAccess::Ready || !self.view.can_create_worktree {
            return Err("the workspace cannot create a managed worktree".into());
        }
        let source = self
            .selection
            .as_ref()
            .ok_or("missing selected project")?
            .checkout
            .clone();
        let checkouts = self.managed_worktree_root()?;
        fs::create_dir_all(&checkouts)?;
        let repository_name = source
            .canonical_path()
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("Project")
            .to_owned();
        let store = WorktreeStore::initialize_tauri(&self.worktree_records)?;
        let manager = WorktreeManager::new(store, CheckoutIdentity::capture(&checkouts)?);
        let record = manager
            .create(source, &Uuid::new_v4().to_string(), &repository_name)
            .await?;
        let checkout = CheckoutIdentity::capture(&record.checkout_path)?;
        self.select(record.checkout_path, checkout, None).await?;
        Ok(())
    }

    fn managed_worktree_root(&self) -> Result<PathBuf, Failure> {
        let profile = self
            .worktree_records
            .parent()
            .ok_or("missing Tauri profile")?;
        let mut name = profile
            .file_name()
            .ok_or("missing profile name")?
            .to_owned();
        name.push("-checkouts");
        Ok(profile.with_file_name(name))
    }

    pub(super) fn pending_worktree_binding(
        &self,
    ) -> Result<Option<WorktreeThreadBinding>, Failure> {
        let checkout = &self
            .selection
            .as_ref()
            .ok_or("missing selected project")?
            .checkout;
        let root = match CheckoutIdentity::capture(&self.managed_worktree_root()?) {
            Ok(root) => root,
            Err(CheckoutError::Io { source, .. }) if source.kind() == io::ErrorKind::NotFound => {
                return Ok(None);
            }
            Err(error) => return Err(error.into()),
        };
        if checkout.canonical_path().parent() != Some(root.canonical_path()) {
            return Ok(None);
        }
        let store = WorktreeStore::open(&self.worktree_records)?;
        let snapshot = store.snapshot()?;
        let record = snapshot.records.iter().find(|record| {
            record.checkout_path == checkout.canonical_path()
                && record.phase == WorktreePhase::Active
        });
        let Some(record) = record else {
            return Ok(None);
        };
        let resume = record.thread_id.clone().map(ThreadId);
        if let Some(thread) = &resume
            && self.store.has_thread_draft(thread)?
        {
            return Ok(None);
        }
        if snapshot.authority != Edition::Tauri {
            return Err("the selected checkout has no Tauri worktree authority".into());
        }
        Ok(Some(WorktreeThreadBinding {
            manager: WorktreeManager::new(store, root),
            record: record.id,
            resume,
        }))
    }
}
