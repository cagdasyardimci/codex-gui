use std::{env, process::Command};

use super::*;

fn record(root: &Path) -> WorktreeRecord {
    let id = Uuid::new_v4();
    WorktreeRecord {
        id,
        task_id: format!("task-{id}"),
        thread_id: None,
        source_project_path: root.join("source"),
        repository_git_directory: root.join("source").join(".git"),
        repository_identity: None,
        branch: format!("codex/task/sample-{id}"),
        checkout_path: root.join("checkouts").join(format!("sample-{id}")),
        checkout_identity: None,
        base_commit: "f".repeat(40),
        source_was_dirty: true,
        created_at: 813_600_000.5,
        phase: WorktreePhase::Preparing,
    }
}

#[test]
fn reopens_durable_records_with_exclusive_edition_and_binding_ownership() {
    let root = tempfile::tempdir().unwrap();
    let records = root.path().join("records");
    let store = WorktreeStore::initialize_tauri(&records).unwrap();
    assert!(matches!(
        store.lock_for(Edition::AppKit),
        Err(StoreError::Authority(Edition::Tauri))
    ));
    let initial = record(root.path());
    let mut active = initial.clone();
    active.thread_id = Some("thread-1".into());
    active.phase = WorktreePhase::Active;
    {
        let owner = store.lock_for(Edition::Tauri).unwrap();
        assert!(owner.load(initial.id).unwrap().is_none());
        owner.save(None, &initial).unwrap();
        assert_eq!(owner.load(initial.id).unwrap(), Some(initial.clone()));
        owner.save(Some(&initial), &active).unwrap();
        assert!(matches!(
            owner.save(Some(&initial), &initial),
            Err(StoreError::Changed)
        ));

        let mut duplicate = record(root.path());
        duplicate.thread_id = active.thread_id.clone();
        assert!(matches!(
            owner.save(None, &duplicate),
            Err(StoreError::Ownership)
        ));
        let mut new_owner = active.clone();
        new_owner.thread_id = Some("replacement".into());
        assert!(matches!(
            owner.save(Some(&active), &new_owner),
            Err(StoreError::Ownership)
        ));
    }
    let reopened = WorktreeStore::initialize_tauri(&records).unwrap();
    let snapshot = reopened.snapshot().unwrap();
    assert_eq!(snapshot.authority, Edition::Tauri);
    assert_eq!(snapshot.records, [active]);
}

#[test]
fn preserves_swift_version_one_records_before_authority_transfer() {
    let root = tempfile::tempdir().unwrap();
    let original = record(root.path());
    let linked_path = root.path().join(record_name(original.id));
    let legacy = serde_json::json!({
        "version": 1,
        "workspace": {
            "id": original.id.to_string().to_uppercase(),
            "taskID": original.task_id,
            "sourceProjectPath": original.source_project_path,
            "repositoryGitDirectory": original.repository_git_directory,
            "branch": original.branch,
            "checkoutPath": original.checkout_path,
            "baseCommit": original.base_commit,
            "sourceWasDirty": original.source_was_dirty,
            "createdAt": original.created_at,
            "phase": "preparing",
        }
    });
    let source_bytes = serde_json::to_vec(&legacy).unwrap();
    fs::write(&linked_path, &source_bytes).unwrap();

    let store = WorktreeStore::open(root.path()).unwrap();
    let snapshot = store.snapshot().unwrap();
    assert_eq!(snapshot.authority, Edition::AppKit);
    assert_eq!(snapshot.records, [original]);
    assert!(matches!(
        store.lock_for(Edition::Tauri),
        Err(StoreError::Authority(Edition::AppKit))
    ));
    assert!(matches!(
        WorktreeStore::initialize_tauri(root.path()),
        Err(StoreError::Authority(Edition::AppKit))
    ));
    assert_eq!(fs::read(linked_path).unwrap(), source_bytes);
    fs::write(
        root.path().join(AUTHORITY_NAME),
        r#"{"version":19,"edition":"tauri"}"#,
    )
    .unwrap();
    assert!(matches!(store.snapshot(), Err(StoreError::InvalidDocument)));
}

#[test]
fn record_lock_excludes_another_process_and_releases_on_drop() {
    const FIXTURE_DIR: &str = "CODEX_GUI_TEST_WORKTREE_RECORDS";
    const FIXTURE_MODE: &str = "CODEX_GUI_TEST_WORKTREE_EXPECT_LOCKED";

    if let Some(records) = env::var_os(FIXTURE_DIR) {
        let store = WorktreeStore::open(Path::new(&records)).unwrap();
        let acquired = store.lock_for(Edition::Tauri);
        if env::var_os(FIXTURE_MODE).is_some() {
            assert!(matches!(acquired, Err(StoreError::Contended)));
        } else {
            assert!(acquired.is_ok());
        }
        return;
    }

    let root = tempfile::tempdir().unwrap();
    let store = WorktreeStore::initialize_tauri(root.path()).unwrap();
    let run_child = |is_locked: bool| {
        let mut command = Command::new(env::current_exe().unwrap());
        command
            .args([
                "--exact",
                "worktree::tests::record_lock_excludes_another_process_and_releases_on_drop",
            ])
            .env(FIXTURE_DIR, root.path())
            .env_remove(FIXTURE_MODE);
        if is_locked {
            command.env(FIXTURE_MODE, "1");
        }
        let output = command.output().unwrap();
        let logs = String::from_utf8_lossy(&output.stdout);
        assert!(
            output.status.success() && logs.contains("1 passed"),
            "{logs}"
        );
    };
    let lock = store.lock_for(Edition::Tauri).unwrap();
    run_child(true);
    drop(lock);
    run_child(false);
}
