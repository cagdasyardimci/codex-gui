use std::time::{SystemTime, UNIX_EPOCH};

use crate::git::{CheckoutGit, GitError, decode_path, nul_fields, parse_oid, terminated_line};

use super::*;

mod recovery;
mod removal;
pub use recovery::{RecoveryKind, WorktreeRecovery};

const GIT_RESPONSE_BYTES: usize = 512 * 1024;
const FOUNDATION_EPOCH: f64 = 978_307_200.0;
const BRANCH_PREFIX: &str = "codex/task/";

#[derive(Debug, Error)]
pub enum WorktreeError {
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Git(#[from] GitError),
    #[error(transparent)]
    Runtime(#[from] crate::workspace::OwnerError),
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error("the managed checkout root is inside a Git checkout or repository")]
    UnsafeRoot,
    #[error("the target checkout path or branch is occupied")]
    Occupied,
    #[error("the recorded checkout no longer matches its Git registration")]
    Ownership,
    #[error("the workspace record does not exist")]
    Unknown,
    #[error("the workspace does not have an active checkout")]
    Inactive,
    #[error("the recorded checkout contains changes or ignored files")]
    Dirty,
}

pub struct WorktreeManager {
    store: WorktreeStore,
    checkouts: CheckoutIdentity,
}

impl WorktreeManager {
    pub fn new(store: WorktreeStore, checkouts: CheckoutIdentity) -> Self {
        Self { store, checkouts }
    }

    pub async fn create(
        &self,
        selected: CheckoutIdentity,
        task_id: &str,
        name: &str,
    ) -> Result<WorktreeRecord, WorktreeError> {
        let locked = self.store.lock_for(Edition::Tauri)?;
        let source = CheckoutGit::new(selected)?;
        let root = CheckoutIdentity::capture(&source.reported_root().await?)?;
        if !source
            .checkout
            .canonical_path()
            .starts_with(root.canonical_path())
        {
            return Err(WorktreeError::Ownership);
        }
        let source = CheckoutGit::new(root)?;
        let repository = repository(&source).await?;
        let registered = registered_paths(&source).await?;
        self.checkouts.revalidate()?;
        let destination = self.checkouts.canonical_path();
        if destination.starts_with(repository.canonical_path())
            || registered.iter().any(|path| destination.starts_with(path))
        {
            return Err(WorktreeError::UnsafeRoot);
        }
        let id = Uuid::new_v4();
        let component = format!("{}-{id}", slug(name));
        let branch = format!("{BRANCH_PREFIX}{component}");
        let checkout_path = destination.join(component);
        let branch_ref = format!("refs/heads/{branch}");
        let (exists, _) = source
            .run(
                ["show-ref", "--verify", "--quiet", &branch_ref],
                GIT_RESPONSE_BYTES,
            )
            .await?;
        if exists.success() {
            return Err(WorktreeError::Occupied);
        }
        if exists.code() != Some(1) {
            return Err(GitError::Exit(exists).into());
        }
        match checkout_path.symlink_metadata() {
            Ok(_) => return Err(WorktreeError::Occupied),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        let base_commit = head(&source).await?;
        // An oversized porcelain response already proves that the source has changes.
        let source_was_dirty = match source
            .success(
                ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
                GIT_RESPONSE_BYTES,
            )
            .await
        {
            Ok(result) => !result.is_empty(),
            Err(GitError::Limit) => true,
            Err(error) => return Err(error.into()),
        };
        let mut preparing = WorktreeRecord {
            id,
            task_id: task_id.trim().to_owned(),
            thread_id: None,
            source_project_path: source.checkout.canonical_path().to_path_buf(),
            repository_git_directory: repository.canonical_path().to_path_buf(),
            repository_identity: Some(repository.storage_key()),
            branch,
            checkout_path,
            checkout_identity: None,
            base_commit,
            source_was_dirty,
            created_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(io::Error::other)?
                .as_secs_f64()
                - FOUNDATION_EPOCH,
            phase: WorktreePhase::Preparing,
        };
        locked.save(None, &preparing)?;
        fs::create_dir(&preparing.checkout_path)?;
        let target = CheckoutIdentity::capture(&preparing.checkout_path)?;
        if target.canonical_path() != preparing.checkout_path {
            return Err(WorktreeError::Ownership);
        }
        let previous = preparing.clone();
        preparing.checkout_identity = Some(target.storage_key());
        locked.save(Some(&previous), &preparing)?;
        repository.revalidate()?;
        self.checkouts.revalidate()?;
        target.revalidate()?;
        let path = git_path(&preparing.checkout_path);
        source
            .success(
                [
                    OsStr::new("worktree"),
                    OsStr::new("add"),
                    OsStr::new("-b"),
                    OsStr::new(&preparing.branch),
                    OsStr::new("--"),
                    path.as_os_str(),
                    OsStr::new(&preparing.base_commit),
                ],
                GIT_RESPONSE_BYTES,
            )
            .await?;

        let checkout = self.verify_checkout(&preparing).await?;
        if head(&checkout).await? != preparing.base_commit {
            return Err(WorktreeError::Ownership);
        }
        let mut active = preparing.clone();
        active.phase = WorktreePhase::Active;
        locked.save(Some(&preparing), &active)?;
        Ok(active)
    }

    pub async fn bind(
        &self,
        id: Uuid,
        thread_id: &str,
        reported_checkout: &Path,
    ) -> Result<WorktreeRecord, WorktreeError> {
        let locked = self.store.lock_for(Edition::Tauri)?;
        let active = locked.load(id)?.ok_or(WorktreeError::Unknown)?;
        if active.phase != WorktreePhase::Active {
            return Err(WorktreeError::Inactive);
        }
        let checkout = self.verify_checkout(&active).await?;
        checkout.checkout.validate_reported(reported_checkout)?;
        let mut bound = active.clone();
        bound.thread_id = Some(thread_id.trim().to_owned());
        locked.save(Some(&active), &bound)?;
        Ok(bound)
    }

    async fn verify_checkout(&self, record: &WorktreeRecord) -> Result<CheckoutGit, WorktreeError> {
        let (source, source_repository) = self.recorded_source(record).await?;
        if !registered_paths(&source)
            .await?
            .contains(&record.checkout_path)
        {
            return Err(WorktreeError::Ownership);
        }
        self.verify_registered(record, &source_repository).await
    }

    async fn recorded_source(
        &self,
        record: &WorktreeRecord,
    ) -> Result<(CheckoutGit, CheckoutIdentity), WorktreeError> {
        self.checkouts.revalidate()?;
        let name = record
            .branch
            .strip_prefix(BRANCH_PREFIX)
            .ok_or(WorktreeError::Ownership)?;
        if !name.ends_with(&format!("-{}", record.id))
            || record.checkout_path.parent() != Some(self.checkouts.canonical_path())
            || record.checkout_path.file_name() != Some(OsStr::new(name))
        {
            return Err(WorktreeError::Ownership);
        }
        let source = CheckoutGit::new(CheckoutIdentity::capture(&record.source_project_path)?)?;
        let source_repository = repository(&source).await?;
        if source_repository.canonical_path() != record.repository_git_directory
            || record
                .repository_identity
                .as_ref()
                .is_some_and(|id| *id != source_repository.storage_key())
        {
            return Err(WorktreeError::Ownership);
        }
        Ok((source, source_repository))
    }

    async fn verify_registered(
        &self,
        record: &WorktreeRecord,
        source_repository: &CheckoutIdentity,
    ) -> Result<CheckoutGit, WorktreeError> {
        let identity = CheckoutIdentity::capture(&record.checkout_path)?;
        if identity.canonical_path() != record.checkout_path
            || record
                .checkout_identity
                .as_ref()
                .is_some_and(|id| *id != identity.storage_key())
        {
            return Err(WorktreeError::Ownership);
        }
        let checkout = CheckoutGit::new(identity)?;
        if &repository(&checkout).await? != source_repository {
            return Err(WorktreeError::Ownership);
        }
        verify_branch(&checkout, &record.branch).await?;
        self.checkouts.revalidate()?;
        Ok(checkout)
    }
}

async fn verify_branch(checkout: &CheckoutGit, branch: &str) -> Result<(), WorktreeError> {
    let (status, reported) = checkout
        .run(["symbolic-ref", "--quiet", "HEAD"], GIT_RESPONSE_BYTES)
        .await?;
    let expected = format!("refs/heads/{branch}");
    if !status.success() || terminated_line(&reported)? != expected.as_bytes() {
        return Err(WorktreeError::Ownership);
    }
    Ok(())
}

async fn repository(git: &CheckoutGit) -> Result<CheckoutIdentity, WorktreeError> {
    git.checkout
        .validate_reported(&git.reported_root().await?)?;
    let result = git
        .success(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            GIT_RESPONSE_BYTES,
        )
        .await?;
    Ok(CheckoutIdentity::capture(&decode_path(terminated_line(
        &result,
    )?)?)?)
}

async fn head(git: &CheckoutGit) -> Result<String, GitError> {
    let result = git
        .success(
            ["rev-parse", "--verify", "HEAD^{commit}"],
            GIT_RESPONSE_BYTES,
        )
        .await?;
    Ok(parse_oid(&result)?.to_owned())
}

async fn registered_paths(git: &CheckoutGit) -> Result<Vec<PathBuf>, WorktreeError> {
    let result = git
        .success(
            ["worktree", "list", "--porcelain", "-z"],
            GIT_RESPONSE_BYTES,
        )
        .await?;
    let mut paths = Vec::new();
    for field in nul_fields(&result)? {
        if let Some(raw) = field.strip_prefix(b"worktree ") {
            let path = decode_path(raw)?;
            if !path.is_absolute() {
                return Err(WorktreeError::Ownership);
            }
            match path.canonicalize() {
                Ok(canonical) => paths.push(canonical),
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    // A removed checkout can remain registered. Normalize its name using
                    // the surviving parent, including Windows' canonical volume prefix.
                    let parent = path.parent().and_then(|parent| parent.canonicalize().ok());
                    let normalized = parent
                        .zip(path.file_name())
                        .map(|(parent, name)| parent.join(name));
                    paths.push(normalized.unwrap_or(path));
                }
                Err(error) => return Err(error.into()),
            }
        }
    }
    Ok(paths)
}

fn slug(name: &str) -> String {
    let slug: String = name
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-")
        .to_ascii_lowercase()
        .chars()
        .take(32)
        .collect();
    match slug.trim_end_matches('-') {
        "" => "task".to_owned(),
        slug => slug.to_owned(),
    }
}

fn git_path(path: &Path) -> &Path {
    #[cfg(windows)]
    return dunce::simplified(path);
    #[cfg(unix)]
    return path;
}

#[cfg(test)]
mod tests;
