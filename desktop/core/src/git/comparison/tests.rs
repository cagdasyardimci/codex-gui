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
