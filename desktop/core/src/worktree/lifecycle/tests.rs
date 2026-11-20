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
    _root: tempfile::TempDir,
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
            _root: root,
        }
    }

    fn manager(&self) -> WorktreeManager {
        WorktreeManager::new(
            WorktreeStore::initialize_tauri(&self.records).unwrap(),
            self.checkouts.clone(),
        )
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
