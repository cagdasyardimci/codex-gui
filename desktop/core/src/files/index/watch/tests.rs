use std::{
    fs,
    io::Write,
    thread,
    time::{Duration, Instant},
};

use notify::event::{CreateKind, Flag, RemoveKind, RenameMode};

use super::*;

fn write(root: &Path, relative: &str) {
    let file = root.join(relative);
    fs::create_dir_all(file.parent().unwrap()).unwrap();
    fs::write(file, relative).unwrap();
}

fn apply(index: &mut ProjectPathIndex, changes: Changes) {
    match changes {
        Changes::Scopes(scopes) => index.refresh_scopes(&scopes).unwrap(),
        Changes::Rebuild | Changes::Restart => index.rebuild().unwrap(),
    }
}

fn compare_clean(index: &ProjectPathIndex) {
    let clean = ProjectPathIndex::scan_with_limit(index.checkout.clone(), index.limit).unwrap();
    assert!(
        index
            .entries
            .iter()
            .map(|entry| &entry.path)
            .eq(clean.entries.iter().map(|entry| &entry.path))
    );
    assert_eq!(index.exhaustive, clean.exhaustive);
}

#[test]
fn groups_rename_and_removal_by_parent_and_preserves_paths_across_an_atomic_save() {
    let scratch = tempfile::tempdir().unwrap();
    for path in [
        "notes/original.md",
        "notes/discard.md",
        "source/detail/save.md",
        "other/untouched.md",
    ] {
        write(scratch.path(), path);
    }
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let root = checkout.canonical_path();
    let paths = [root.join("notes/original.md"), root.join("source/moved.md")];
    let mut index = ProjectPathIndex::scan(checkout.clone()).unwrap();
    fs::rename(&paths[0], &paths[1]).unwrap();
    fs::remove_file(root.join("notes/discard.md")).unwrap();
    let mut changes = Changes::default();
    changes.observe(
        event_path(root),
        Event::new(EventKind::Modify(ModifyKind::Name(RenameMode::Both)))
            .add_path(paths[0].clone())
            .add_path(paths[1].clone()),
    );
    changes.observe(
        event_path(root),
        Event::new(EventKind::Remove(RemoveKind::File)).add_path(root.join("notes/discard.md")),
    );
    changes.observe(
        event_path(root),
        Event::new(EventKind::Create(CreateKind::File))
            .add_path(root.join("source/detail/example.md")),
    );
    let Changes::Scopes(scopes) = &changes else {
        panic!("expected scoped updates")
    };
    assert_eq!(
        scopes,
        &BTreeSet::from([PathBuf::from("notes"), PathBuf::from("source")])
    );
    let before = index.revision;
    apply(&mut index, changes);
    compare_clean(&index);
    assert_ne!(index.revision, before);

    let mut edited = tempfile::NamedTempFile::new_in(root.join("source/detail")).unwrap();
    edited.write_all(b"atomic replacement").unwrap();
    let temporary = edited.path().to_path_buf();
    let target = root.join("source/detail/save.md");
    edited.persist(&target).unwrap();
    let mut changes = Changes::default();
    changes.observe(
        event_path(root),
        Event::new(EventKind::Modify(ModifyKind::Name(RenameMode::Both)))
            .add_path(temporary)
            .add_path(target),
    );
    let revision = index.revision;
    apply(&mut index, changes);
    compare_clean(&index);
    assert_eq!(index.revision, revision);
}

#[test]
fn rebuilds_when_a_capped_index_needs_hidden_candidates_or_notifications_overflow() {
    let scratch = tempfile::tempdir().unwrap();
    for path in ["a/keep.md", "b/remove.md", "z/promote.md"] {
        write(scratch.path(), path);
    }
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let root = checkout.canonical_path();
    let mut index = ProjectPathIndex::scan_with_limit(checkout.clone(), 2).unwrap();
    assert!(!index.exhaustive);
    assert!(index.search("promote").unwrap().is_empty());
    fs::remove_file(root.join("b/remove.md")).unwrap();
    apply(&mut index, Changes::Scopes(BTreeSet::from(["b".into()])));
    compare_clean(&index);
    assert_eq!(
        index.search("promote").unwrap()[0].display_path,
        "z/promote.md"
    );

    write(root, "b/new.md");
    let mut changes = Changes::default();
    changes.observe(
        event_path(root),
        Event::new(EventKind::Other).set_flag(Flag::Rescan),
    );
    assert!(matches!(changes, Changes::Rebuild));
    apply(&mut index, changes);
    compare_clean(&index);
    assert!(index.search("promote").unwrap().is_empty());
    let mut changes = Changes::default();
    for scope in 0..=MAX_SCOPES {
        changes.observe(
            event_path(root),
            Event::new(EventKind::Create(CreateKind::File))
                .add_path(root.join(format!("dir-{scope}/entry.md"))),
        );
    }
    assert!(matches!(changes, Changes::Rebuild));

    let mut index = ProjectPathIndex::scan(checkout.clone()).unwrap();
    index.bytes_upper_bound = MAX_DISCOVERY_BYTES - 1;
    write(root, "b/byte-budget.md");
    write(root, "z/also-discovered.md");
    apply(&mut index, Changes::Scopes(BTreeSet::from(["b".into()])));
    compare_clean(&index);
    assert_eq!(index.search("also-discovered").unwrap().len(), 1);
}

#[test]
fn watches_native_rename_and_rejects_a_replaced_checkout() {
    let scratch = tempfile::tempdir().unwrap();
    let root = scratch.path().join("project");
    write(&root, "notes/original.md");
    let checkout = CheckoutIdentity::capture(&root).unwrap();
    let mut watcher = WatchedProjectPaths::new(checkout);
    let old = watcher.search("original").unwrap().remove(0);
    assert!(
        watcher.watcher.is_some(),
        "the native observer did not start"
    );
    fs::rename(
        root.join("notes/original.md"),
        root.join("notes/renamed.md"),
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(6);
    loop {
        let matched = watcher.search("renamed").unwrap();
        assert!(watcher.watcher.is_some(), "the native observer stopped");
        if let [new] = matched.as_slice() {
            assert_ne!(old.id.revision, new.id.revision);
            assert!(watcher.search("original").unwrap().is_empty());
            break;
        }
        assert!(
            Instant::now() < deadline,
            "the native observer did not publish the rename"
        );
        thread::sleep(Duration::from_millis(20));
    }
    fs::rename(&root, scratch.path().join("retired")).unwrap();
    write(&root, "notes/substitute.md");
    assert!(matches!(
        watcher.search("substitute"),
        Err(FileError::Checkout(_))
    ));
    assert!(watcher.watcher.is_none());
    let mut fresh = WatchedProjectPaths::new(CheckoutIdentity::capture(&root).unwrap());
    assert_eq!(
        fresh.search("substitute").unwrap()[0].display_path,
        "notes/substitute.md"
    );
}

#[cfg(unix)]
#[test]
fn drops_a_scope_replaced_by_a_symbolic_link_without_indexing_the_destination() {
    let scratch = tempfile::tempdir().unwrap();
    let root = scratch.path().join("checkout");
    let outside = scratch.path().join("outside");
    write(&root, "notes/scoped/owned.md");
    write(&outside, "unrelated.md");
    let mut index = ProjectPathIndex::scan(CheckoutIdentity::capture(&root).unwrap()).unwrap();
    fs::remove_dir_all(root.join("notes/scoped")).unwrap();
    std::os::unix::fs::symlink(&outside, root.join("notes/scoped")).unwrap();
    apply(
        &mut index,
        Changes::Scopes(BTreeSet::from(["notes/scoped".into()])),
    );
    compare_clean(&index);
    assert!(index.search("").unwrap().is_empty());
}
