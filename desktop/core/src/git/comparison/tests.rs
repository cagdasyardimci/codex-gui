use std::{fs, process::Command};

use super::*;

fn git(root: &Path, args: &[&str]) -> Vec<u8> {
    let output = Command::new("git")
        .current_dir(root)
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

fn initialize() -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    let path = root.path();
    git(path, &["init", "--initial-branch=main"]);
    fs::create_dir(path.join("empty-hooks")).unwrap();
    git(
        path,
        &["config", "--local", "core.hooksPath", "empty-hooks"],
    );
    git(
        path,
        &["config", "--local", "user.name", "Comparison Fixture"],
    );
    git(
        path,
        &["config", "--local", "user.email", "fixture@example.invalid"],
    );
    root
}

#[tokio::test]
async fn selects_refs_and_commits_independently_and_reads_the_pinned_rename_lazily() {
    let scratch = initialize();
    let root = scratch.path();
    let old = "old λ [draft].txt";
    let new = "new λ [draft].txt";
    fs::write(root.join(old), "original contents\n").unwrap();
    git(root, &["add", "--", old]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Base"]);
    git(root, &["branch", "baseline"]);
    git(root, &["mv", "--", old, new]);
    let huge = "the unrelated line belongs in another lazy patch\n".repeat(185_000);
    fs::write(root.join("large.txt"), huge).unwrap();
    git(root, &["add", "large.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Move and add"]);
    git(root, &["branch", "review"]);
    git(root, &["update-ref", "refs/remotes/origin/preview", "HEAD"]);
    git(
        root,
        &[
            "symbolic-ref",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/preview",
        ],
    );
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();

    let branches = service.branches().await.unwrap();
    assert_eq!(branches.current.as_deref(), Some("refs/heads/main"));
    assert_eq!(
        branches
            .choices
            .iter()
            .map(|branch| branch.reference.as_str())
            .collect::<Vec<_>>(),
        [
            "refs/heads/baseline",
            "refs/heads/review",
            "refs/remotes/origin/preview"
        ]
    );
    let commits = service.recent_commits().await.unwrap();
    assert_eq!(
        commits
            .iter()
            .map(|commit| commit.subject.as_str())
            .collect::<Vec<_>>(),
        ["Move and add", "Base"]
    );

    let captured = service
        .compare(ComparisonSpec::Between {
            base: "refs/heads/baseline".into(),
            target: "refs/heads/review".into(),
        })
        .await
        .unwrap();
    assert_eq!(
        captured.sides(),
        (
            &ComparisonSide::Object(commits[1].oid.clone()),
            &ComparisonSide::Object(commits[0].oid.clone()),
        )
    );
    let renamed = captured
        .files()
        .find(|file| file.kind == ComparisonKind::Renamed)
        .unwrap();
    assert_eq!(
        (renamed.before.as_deref(), renamed.after.as_deref()),
        (Some(old), Some(new))
    );
    assert_eq!(captured.files().len(), 2);

    git(root, &["branch", "--force", "review", "baseline"]);
    let detail = captured.detail(renamed.id).await.unwrap();
    let patch = String::from_utf8(detail).unwrap();
    assert!(
        patch.contains("similarity index 100%")
            && patch.contains("rename from ")
            && patch.contains("rename to ")
    );
    assert!(!patch.contains("large.txt"));
    let large = captured
        .files()
        .find(|file| file.after.as_deref() == Some("large.txt"))
        .unwrap();
    assert!(matches!(
        captured.detail(large.id).await,
        Err(GitError::Limit)
    ));

    let root_commit = service
        .compare(ComparisonSpec::Commit("baseline".into()))
        .await
        .unwrap();
    let root_entry = root_commit.files().next().unwrap();
    assert_eq!(root_entry.kind, ComparisonKind::Added);
    assert!(matches!(
        root_commit.detail(renamed.id).await,
        Err(GitError::RetiredFile)
    ));
    assert!(
        String::from_utf8(root_commit.detail(root_entry.id).await.unwrap())
            .unwrap()
            .contains("+original contents")
    );
    let moved = service
        .compare(ComparisonSpec::Between {
            base: "baseline".into(),
            target: "review".into(),
        })
        .await
        .unwrap();
    assert_eq!(moved.files().len(), 0);
    assert!(matches!(
        service
            .compare(ComparisonSpec::Commit("--help".into()))
            .await,
        Err(GitError::InvalidRevision)
    ));
}

#[tokio::test]
async fn compares_working_tree_scopes_without_running_configured_clean_filters() {
    let scratch = initialize();
    let root = scratch.path();
    fs::write(root.join("a.txt"), "initial a\n").unwrap();
    fs::write(root.join("b.txt"), "initial b\n").unwrap();
    git(root, &["add", "a.txt", "b.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Start"]);
    git(root, &["branch", "comparison-base"]);
    fs::write(root.join("a.txt"), "staged a\n").unwrap();
    git(root, &["add", "a.txt"]);
    fs::write(root.join("b.txt"), "unstaged b\n").unwrap();
    fs::write(root.join("untracked.txt"), "untracked\n").unwrap();
    git(
        root,
        &["config", "--local", "filter.fixture.clean", "exit 19"],
    );
    git(
        root,
        &["config", "--local", "filter.fixture.required", "true"],
    );
    fs::write(root.join(".gitattributes"), "b.txt filter=fixture\n").unwrap();
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    for (scope, expected) in [
        (ComparisonSpec::Staged, &["a.txt"][..]),
        (ComparisonSpec::Unstaged, &["b.txt"][..]),
        (ComparisonSpec::Uncommitted, &["a.txt", "b.txt"][..]),
        (
            ComparisonSpec::WorkingTreeAgainstBranch(Some("refs/heads/comparison-base".into())),
            &["a.txt", "b.txt"][..],
        ),
    ] {
        let comparison = service.compare(scope).await.unwrap();
        assert_eq!(
            comparison
                .files()
                .map(|file| file.after.unwrap())
                .collect::<Vec<_>>(),
            expected
        );
        for file in comparison.files() {
            let patch = comparison.detail(file.id).await.unwrap();
            assert!(patch.starts_with(b"diff --git "));
        }
    }
}

#[tokio::test]
async fn exports_exact_bytes_and_rejects_a_changed_file_as_one_comparison() {
    let scratch = initialize();
    let root = scratch.path();
    fs::write(root.join("a.txt"), "original a\n").unwrap();
    fs::write(root.join("b.bin"), [0, 1, 2, 3]).unwrap();
    git(root, &["add", "a.txt", "b.bin"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Base"]);
    fs::write(root.join("a.txt"), "changed  a\n").unwrap();
    fs::write(root.join("b.bin"), [0, 1, 4, 3]).unwrap();
    let expected = git(
        root,
        &[
            "diff",
            "--no-color",
            "--full-index",
            "--binary",
            "--unified=2147483647",
            "--find-renames",
            "--find-copies",
            "HEAD",
            "--",
        ],
    );
    assert!(
        expected
            .windows(b"GIT binary patch".len())
            .any(|window| window == b"GIT binary patch")
    );
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    let snapshot = service.compare(ComparisonSpec::Uncommitted).await.unwrap();
    fs::write(root.join("untracked.txt"), "outside the comparison").unwrap();
    assert_eq!(snapshot.export_patch().await.unwrap(), expected);

    let binary = snapshot
        .files()
        .find(|file| file.after.as_deref() == Some("b.bin"))
        .unwrap();
    fs::write(root.join("b.bin"), [0, 1, 5, 3]).unwrap();
    assert!(matches!(
        snapshot.detail(binary.id).await,
        Err(GitError::StaleComparison)
    ));
    assert!(matches!(
        snapshot.export_patch().await,
        Err(GitError::StaleComparison)
    ));
    assert!(
        service
            .compare(ComparisonSpec::Uncommitted)
            .await
            .unwrap()
            .export_patch()
            .await
            .unwrap()
            != expected
    );
}

#[tokio::test]
async fn export_pins_commit_objects_and_checks_the_captured_index() {
    let scratch = initialize();
    let root = scratch.path();
    fs::write(root.join("a.txt"), "base\n").unwrap();
    git(root, &["add", "a.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Base"]);
    fs::write(root.join("a.txt"), "committed\n").unwrap();
    git(root, &["add", "a.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Edit"]);
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    let commit = service
        .compare(ComparisonSpec::Commit("HEAD".into()))
        .await
        .unwrap();
    let exact_commit = git(
        root,
        &[
            "diff",
            "--no-color",
            "--full-index",
            "--binary",
            "--unified=2147483647",
            "HEAD^",
            "HEAD",
            "--",
        ],
    );

    fs::write(root.join("a.txt"), "staged change\n").unwrap();
    git(root, &["add", "a.txt"]);
    let staged = service.compare(ComparisonSpec::Staged).await.unwrap();
    let exact_index = git(
        root,
        &[
            "diff",
            "--cached",
            "--no-color",
            "--full-index",
            "--binary",
            "--unified=2147483647",
            "HEAD",
            "--",
        ],
    );
    fs::write(root.join("a.txt"), "unstaged edit\n").unwrap();
    assert_eq!(staged.export_patch().await.unwrap(), exact_index);
    assert_eq!(commit.export_patch().await.unwrap(), exact_commit);
    git(root, &["add", "a.txt"]);
    assert!(matches!(
        staged.export_patch().await,
        Err(GitError::StaleComparison)
    ));
    assert_eq!(commit.export_patch().await.unwrap(), exact_commit);
}

#[cfg(unix)]
#[tokio::test]
async fn exports_link_content_without_opening_the_link_target() {
    use std::os::unix::fs::symlink;

    let scratch = initialize();
    let root = scratch.path();
    let tracked = root.join("alias");
    symlink("missing-source-a", &tracked).unwrap();
    git(root, &["add", "alias"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Base link"]);
    fs::remove_file(&tracked).unwrap();
    symlink("missing-source-b", &tracked).unwrap();
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    let snapshot = service.compare(ComparisonSpec::Uncommitted).await.unwrap();
    let bytes = snapshot.export_patch().await.unwrap();
    assert!(
        String::from_utf8(bytes)
            .unwrap()
            .contains("+missing-source-b")
    );
    fs::remove_file(&tracked).unwrap();
    symlink("missing-source-c", &tracked).unwrap();
    assert!(matches!(
        snapshot.export_patch().await,
        Err(GitError::StaleComparison)
    ));
}

#[tokio::test]
async fn captures_gitlink_head_and_local_changes_without_erasing_the_nested_checkout() {
    let scratch = initialize();
    let root = scratch.path();
    let nested = root.join("linked");
    fs::create_dir(&nested).unwrap();
    git(&nested, &["init", "--initial-branch=main"]);
    git(
        &nested,
        &["config", "--local", "core.hooksPath", "empty-hooks"],
    );
    git(&nested, &["config", "--local", "user.name", "Fixture"]);
    git(
        &nested,
        &["config", "--local", "user.email", "fixture@example.invalid"],
    );
    fs::write(nested.join("file.txt"), "base\n").unwrap();
    git(&nested, &["add", "file.txt"]);
    git(&nested, &["commit", "--no-gpg-sign", "-m", "Nested base"]);
    git(root, &["add", "linked"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Capture gitlink"]);
    fs::write(nested.join("file.txt"), "changed\n").unwrap();
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    let snapshot = service.compare(ComparisonSpec::Uncommitted).await.unwrap();
    assert_eq!(snapshot.files().len(), 1);
    let patch = String::from_utf8(snapshot.export_patch().await.unwrap()).unwrap();
    assert!(patch.contains("Subproject commit") && patch.contains("-dirty"));
    git(&nested, &["add", "file.txt"]);
    git(
        &nested,
        &["commit", "--no-gpg-sign", "-m", "Advance gitlink"],
    );
    assert!(matches!(
        snapshot.export_patch().await,
        Err(GitError::StaleComparison)
    ));
}

#[tokio::test]
async fn reuses_pinned_outputs_and_keys_them_to_effective_diff_policy() {
    let scratch = initialize();
    let root = scratch.path();
    fs::write(root.join("file.txt"), "before\n").unwrap();
    git(root, &["add", "file.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Base"]);
    fs::write(root.join("file.txt"), "after\n").unwrap();
    git(root, &["add", "file.txt"]);
    git(root, &["commit", "--no-gpg-sign", "-m", "Target"]);
    let service = GitComparisons::open(CheckoutIdentity::capture(root).unwrap())
        .await
        .unwrap();
    let request = ComparisonSpec::Commit("HEAD".into());
    let first = service.compare(request.clone()).await.unwrap();
    let expected = first.export_patch().await.unwrap();
    let file = first.files().next().unwrap();
    assert_eq!(first.detail(file.id).await.unwrap(), expected);
    if first.pinned.is_none() {
        // Older Git can still render the immutable commit pair without sharing results.
        let uncached = service.compare(request).await.unwrap();
        assert!(!Arc::ptr_eq(&first.entries, &uncached.entries));
        return;
    }

    fs::write(root.join(".gitattributes"), "file.txt -diff\n").unwrap();
    fs::write(root.join("file.txt"), "worktree update\n").unwrap();
    let repeated = service.compare(request.clone()).await.unwrap();
    assert!(Arc::ptr_eq(&first.entries, &repeated.entries));
    let shared = repeated.shared.as_ref().unwrap();
    assert_eq!(shared.get_patch(Some(file.id)).unwrap().as_ref(), expected);
    assert_eq!(shared.get_patch(None).unwrap().as_ref(), expected);
    assert_eq!(repeated.export_patch().await.unwrap(), expected);

    let working = service.compare(ComparisonSpec::Uncommitted).await.unwrap();
    assert!(working.shared.is_none());
    fs::write(root.join("file.txt"), "worktree change\n").unwrap();
    assert!(matches!(
        working.export_patch().await,
        Err(GitError::StaleComparison)
    ));

    git(root, &["config", "--local", "diff.algorithm", "histogram"]);
    assert!(matches!(
        first.export_patch().await,
        Err(GitError::StaleComparison)
    ));
    let updated = service.compare(request.clone()).await.unwrap();
    assert!(!Arc::ptr_eq(&first.entries, &updated.entries));
    fs::write(
        root.join(".git").join("info").join("attributes"),
        "file.txt -diff\n",
    )
    .unwrap();
    assert!(matches!(
        updated.export_patch().await,
        Err(GitError::StaleComparison)
    ));
    let binary = service
        .compare(request)
        .await
        .unwrap()
        .export_patch()
        .await
        .unwrap();
    assert!(
        binary
            .windows(b"GIT binary patch".len())
            .any(|bytes| bytes == b"GIT binary patch")
    );
}
