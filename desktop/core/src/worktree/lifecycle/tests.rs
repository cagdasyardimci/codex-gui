use std::process::Command;

use super::*;

fn git(path: &Path, args: &[&str]) -> Vec<u8> {
    let output = Command::new("git")
        .current_dir(path)
        .args(args)
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output.stdout
}

struct Fixture {
    root: tempfile::TempDir,
    source: PathBuf,
    records: PathBuf,
    checkouts: CheckoutIdentity,
}

impl Fixture {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source λ");
        let checkouts = root.path().join("managed checkouts");
        fs::create_dir(&source).unwrap();
        fs::create_dir(&checkouts).unwrap();
        fs::create_dir(source.join("fixture-hooks")).unwrap();
        git(&source, &["init", "--initial-branch=initial"]);
        git(
            &source,
            &["config", "--local", "core.hooksPath", "fixture-hooks"],
        );
        git(&source, &["config", "--local", "user.name", "Fixture"]);
        git(
            &source,
            &["config", "--local", "user.email", "fixture@example.invalid"],
        );
        fs::write(source.join("tracked.txt"), "committed").unwrap();
        git(&source, &["add", "tracked.txt"]);
        git(&source, &["commit", "--no-gpg-sign", "-m", "Fixture"]);
        Self {
            records: root.path().join("records"),
            source,
            checkouts: CheckoutIdentity::capture(&checkouts).unwrap(),
            root,
        }
    }

    fn manager(&self) -> WorktreeManager {
        WorktreeManager::new(
            WorktreeStore::initialize_tauri(&self.records).unwrap(),
            self.checkouts.clone(),
        )
    }

    async fn interrupt_creation(&self) -> WorktreeRecord {
        let hooks = self.source.join("fixture-hooks");
        let hook = hooks.join("post-checkout");
        fs::write(&hook, "#!/bin/sh\nexit 1\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&hook, fs::Permissions::from_mode(0o755)).unwrap();
        }
        git(
            &self.source,
            &[
                "config",
                "--local",
                "core.hooksPath",
                hooks.to_str().unwrap(),
            ],
        );
        let manager = self.manager();
        let source = CheckoutIdentity::capture(&self.source).unwrap();
        let result = manager.create(source, "interrupted", "Incomplete").await;
        assert!(
            matches!(result, Err(WorktreeError::Git(GitError::Exit(_)))),
            "{result:?}"
        );
        let snapshot = manager.store.snapshot().unwrap();
        assert_eq!(snapshot.records.len(), 1);
        let record = snapshot.records.into_iter().next().unwrap();
        assert_eq!(record.phase, WorktreePhase::Preparing);
        assert!(record.checkout_identity.is_some());
        assert_eq!(
            fs::read(record.checkout_path.join("tracked.txt")).unwrap(),
            b"committed"
        );
        record
    }
}

#[tokio::test]
async fn creates_from_committed_head_and_binds_the_verified_captured_checkout() {
    let fixture = Fixture::new();
    let source = &fixture.source;
    let source_file = source.join("tracked.txt");
    let nested = source.join("drafts");
    fs::create_dir(&nested).unwrap();
    fs::write(&source_file, "staged").unwrap();
    git(source, &["add", "tracked.txt"]);
    fs::write(&source_file, "unstaged").unwrap();
    fs::write(nested.join("note.txt"), "untracked").unwrap();

    let manager = fixture.manager();
    let selected = CheckoutIdentity::capture(&nested).unwrap();
    let created = manager
        .create(selected.clone(), " task ", "Draft & Review")
        .await
        .unwrap();
    assert_eq!(created.phase, WorktreePhase::Active);
    assert_eq!(created.task_id, "task");
    assert!(created.source_was_dirty);
    assert!(created.repository_identity.is_some());
    assert!(created.checkout_identity.is_some());
    assert!(created.branch.starts_with("codex/task/draft-review-"));
    assert_eq!(
        fs::read(created.checkout_path.join("tracked.txt")).unwrap(),
        b"committed"
    );
    assert!(!created.checkout_path.join("drafts").exists());
    assert_eq!(fs::read(&source_file).unwrap(), b"unstaged");
    assert_eq!(git(source, &["show", ":tracked.txt"]), b"staged");
    assert_eq!(fs::read(nested.join("note.txt")).unwrap(), b"untracked");
    assert!(matches!(
        manager.create(selected, "task", "Another").await,
        Err(WorktreeError::Store(StoreError::Ownership))
    ));
    assert!(matches!(
        manager.bind(created.id, "wrong", source).await,
        Err(WorktreeError::Checkout(CheckoutError::Mismatch { .. }))
    ));
    let bound = fixture
        .manager()
        .bind(created.id, "thread-1", &created.checkout_path)
        .await
        .unwrap();
    assert_eq!(bound.thread_id.as_deref(), Some("thread-1"));
    assert_eq!(
        fixture.manager().store.snapshot().unwrap().records,
        std::slice::from_ref(&bound)
    );

    git(&bound.checkout_path, &["checkout", "--detach"]);
    assert!(matches!(
        manager
            .bind(bound.id, "thread-1", &bound.checkout_path)
            .await,
        Err(WorktreeError::Ownership)
    ));
    assert_eq!(manager.store.snapshot().unwrap().records, [bound]);
}

#[tokio::test]
async fn declines_a_managed_root_within_an_existing_git_checkout() {
    let fixture = Fixture::new();
    let source = CheckoutIdentity::capture(&fixture.source).unwrap();
    let nested = fixture.source.join("unsafe-root");
    fs::create_dir(&nested).unwrap();
    let manager = WorktreeManager::new(
        WorktreeStore::initialize_tauri(&fixture.records).unwrap(),
        CheckoutIdentity::capture(&nested).unwrap(),
    );
    assert!(matches!(
        manager.create(source, "task", "Name").await,
        Err(WorktreeError::UnsafeRoot)
    ));
    assert!(manager.store.snapshot().unwrap().records.is_empty());
    assert_eq!(fs::read_dir(nested).unwrap().count(), 0);
}

#[tokio::test]
async fn adopts_the_original_checkout_after_git_reports_a_failed_hook() {
    let fixture = Fixture::new();
    let preparing = fixture.interrupt_creation().await;
    let restarted = fixture.manager();
    let results = restarted.recover().await.unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].kind, RecoveryKind::Active);
    assert_eq!(results[0].record.phase, WorktreePhase::Active);
    assert_eq!(
        results[0].record.checkout_identity,
        preparing.checkout_identity
    );
    assert_eq!(fixture.manager().recover().await.unwrap(), results);
}

#[tokio::test]
async fn rejects_a_substitute_even_when_it_reuses_the_git_registration_and_branch() {
    let fixture = Fixture::new();
    let preparing = fixture.interrupt_creation().await;
    let path = &preparing.checkout_path;
    let original = path.with_extension("original");
    fs::rename(path, &original).unwrap();
    fs::create_dir(path).unwrap();
    fs::copy(original.join(".git"), path.join(".git")).unwrap();
    fs::copy(original.join("tracked.txt"), path.join("tracked.txt")).unwrap();
    let branch = git(path, &["symbolic-ref", "--quiet", "HEAD"]);
    assert_eq!(
        terminated_line(&branch).unwrap(),
        format!("refs/heads/{}", preparing.branch).as_bytes()
    );
    let results = fixture.manager().recover().await.unwrap();
    assert_eq!(
        results,
        [WorktreeRecovery {
            record: preparing,
            kind: RecoveryKind::OwnershipConflict
        }]
    );
    assert!(original.join("tracked.txt").is_file());
}

#[tokio::test]
async fn reconciles_removal_only_from_the_actual_checkout_and_registration() {
    let fixture = Fixture::new();
    let manager = fixture.manager();
    let created = manager
        .create(
            CheckoutIdentity::capture(&fixture.source).unwrap(),
            "task",
            "Temporary",
        )
        .await
        .unwrap();
    let mut removing = created.clone();
    removing.phase = WorktreePhase::Removing;
    let mark_removing = || {
        let lock = manager.store.lock_for(Edition::Tauri).unwrap();
        lock.save(Some(&created), &removing).unwrap();
    };
    mark_removing();
    assert_eq!(
        manager.recover().await.unwrap(),
        [WorktreeRecovery {
            record: created.clone(),
            kind: RecoveryKind::RemovalInterrupted
        }]
    );
    mark_removing();
    let target = git_path(&created.checkout_path).to_str().unwrap();
    git(&fixture.source, &["worktree", "remove", "--", target]);
    let results = manager.recover().await.unwrap();
    assert_eq!(results[0].kind, RecoveryKind::CheckoutRemoved);
    assert_eq!(results[0].record.phase, WorktreePhase::CheckoutRemoved);
    assert_eq!(fixture.manager().recover().await.unwrap(), results);
    git(
        &fixture.source,
        &[
            "show-ref",
            "--verify",
            "--quiet",
            &format!("refs/heads/{}", created.branch),
        ],
    );
}

#[tokio::test]
async fn cleanup_refuses_ignored_files_and_preserves_the_clean_branch_and_bound_record() {
    use crate::{storage::attachments::AttachmentStore, workspace::RuntimeOwners};

    let fixture = Fixture::new();
    let manager = fixture.manager();
    let source = CheckoutIdentity::capture(&fixture.source).unwrap();
    let store = AttachmentStore::open(&fixture.root.path().join("workspace.sqlite3")).unwrap();
    let owners = RuntimeOwners::new(store);
    let created = manager
        .create(source.clone(), "clean", "Managed")
        .await
        .unwrap();
    let bound = manager
        .bind(created.id, "thread-1", &created.checkout_path)
        .await
        .unwrap();
    let checkout = CheckoutIdentity::capture(&bound.checkout_path).unwrap();
    let unrelated = owners.reserve_cleanup(&source).unwrap();
    assert!(matches!(
        manager.remove_clean(bound.id, unrelated).await,
        Err(WorktreeError::Ownership)
    ));

    let excludes = fixture.source.join(".git").join("info").join("exclude");
    fs::write(excludes, "settings.local\n").unwrap();
    let ignored = bound.checkout_path.join("settings.local");
    fs::write(&ignored, "retained settings").unwrap();
    let reservation = owners.reserve_cleanup(&checkout).unwrap();
    assert!(matches!(
        manager.remove_clean(bound.id, reservation).await,
        Err(WorktreeError::Dirty)
    ));
    assert_eq!(fs::read(&ignored).unwrap(), b"retained settings");
    assert_eq!(
        manager.store.snapshot().unwrap().records,
        std::slice::from_ref(&bound)
    );
    fs::remove_file(ignored).unwrap();
    fs::write(fixture.source.join("source-only.txt"), "untouched").unwrap();

    let path = git_path(&bound.checkout_path).to_str().unwrap();
    git(&fixture.source, &["worktree", "lock", "--", path]);
    let reservation = owners.reserve_cleanup(&checkout).unwrap();
    assert!(matches!(
        manager.remove_clean(bound.id, reservation).await,
        Err(WorktreeError::Git(GitError::Exit(_)))
    ));
    assert_eq!(
        manager.store.snapshot().unwrap().records[0].phase,
        WorktreePhase::Removing
    );
    assert_eq!(
        manager.recover().await.unwrap()[0].kind,
        RecoveryKind::RemovalInterrupted
    );
    git(&fixture.source, &["worktree", "unlock", "--", path]);

    let reservation = owners.reserve_cleanup(&checkout).unwrap();
    let removed = manager.remove_clean(bound.id, reservation).await.unwrap();
    assert_eq!(removed.phase, WorktreePhase::CheckoutRemoved);
    assert_eq!(removed.thread_id, bound.thread_id);
    assert_eq!(removed.branch, bound.branch);
    assert_eq!(removed.checkout_identity, bound.checkout_identity);
    assert!(!bound.checkout_path.exists());
    assert_eq!(
        fs::read(fixture.source.join("source-only.txt")).unwrap(),
        b"untouched"
    );
    let reference = format!("refs/heads/{}", removed.branch);
    let returned = git(&fixture.source, &["rev-parse", "--verify", &reference]);
    assert_eq!(parse_oid(&returned).unwrap(), removed.base_commit);
    assert_eq!(
        fixture.manager().store.snapshot().unwrap().records,
        [removed]
    );
}
