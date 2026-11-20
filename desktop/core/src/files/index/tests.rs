use std::fs;

use super::*;
use crate::files::CheckoutFiles;

fn write_paths(root: &Path, paths: &[&str]) {
    for path in paths {
        let target = root.join(path);
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::write(target, path).unwrap();
    }
}

fn labels(index: &ProjectPathIndex, query: &str) -> Vec<String> {
    index
        .search(query)
        .unwrap()
        .into_iter()
        .map(|entry| entry.display_path)
        .collect()
}

#[test]
fn ranks_visible_paths_by_the_filename_match_then_the_relative_path() {
    let root = tempfile::tempdir().unwrap();
    write_paths(
        root.path(),
        &[
            "a/Café.md",
            "b/Café.md.txt",
            "c/a-Café.md.txt",
            "Café.md folder/ordinary.txt",
            "z/Café.md folder/word.txt",
            "notes/.Café.md",
            ".private/Café.md",
            "node_modules/Café.md",
            "build/Café.md",
            "Example.app/Café.md",
            "Example.xcodeproj/Café.md",
        ],
    );
    let checkout = CheckoutIdentity::capture(root.path()).unwrap();
    let index = ProjectPathIndex::scan(checkout.clone()).unwrap();
    assert_eq!(
        labels(&index, " CAFÉ.MD "),
        [
            "a/Café.md",
            "b/Café.md.txt",
            "c/a-Café.md.txt",
            "Café.md folder/ordinary.txt",
            "z/Café.md folder/word.txt",
        ]
    );
    let first = index.search("café.md").unwrap().remove(0);
    assert_eq!(index.search("cafe\u{0301}.md").unwrap()[0], first);
    let mut files = CheckoutFiles::new(checkout.clone());
    let handle = files.issue(index.relative_path(first.id).unwrap()).unwrap();
    assert_eq!(files.read(handle.id).unwrap().bytes, "a/Café.md".as_bytes());
    let rebuilt = ProjectPathIndex::scan(checkout).unwrap();
    assert!(matches!(
        rebuilt.relative_path(first.id),
        Err(FileError::InvalidHandle)
    ));
}

#[test]
fn caps_files_in_native_path_order_and_caps_each_search() {
    let root = tempfile::tempdir().unwrap();
    for position in (0..25).rev() {
        fs::write(root.path().join(format!("haystack-{position:02}.md")), "").unwrap();
    }
    let checkout = CheckoutIdentity::capture(root.path()).unwrap();
    let capped = ProjectPathIndex::scan_with_limit(checkout.clone(), 4).unwrap();
    assert_eq!(
        labels(&capped, " "),
        [
            "haystack-00.md",
            "haystack-01.md",
            "haystack-02.md",
            "haystack-03.md"
        ]
    );
    assert!(capped.search("haystack-09").unwrap().is_empty());
    let full = ProjectPathIndex::scan(checkout).unwrap();
    let first_page: Vec<_> = (0..12)
        .map(|position| format!("haystack-{position:02}.md"))
        .collect();
    assert_eq!(labels(&full, "haystack"), first_page);
    assert!(matches!(
        full.search(&"x".repeat(MAX_QUERY_BYTES + 1)),
        Err(FileError::TooLarge)
    ));
}

#[test]
fn refuses_a_substituted_checkout_and_excludes_link_targets() {
    let scratch = tempfile::tempdir().unwrap();
    let root = scratch.path().join("checkout");
    let outside = scratch.path().join("outside");
    write_paths(&root, &["inside.md"]);
    write_paths(&outside, &["outside.md"]);
    let link = root.join("link");
    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;
        symlink(&outside, &link).unwrap();
        symlink(root.join("inside.md"), root.join("alias.md")).unwrap();
        symlink(root.join("gone.md"), root.join("dangling.md")).unwrap();
    }
    #[cfg(windows)]
    assert!(
        std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&outside)
            .output()
            .unwrap()
            .status
            .success()
    );
    let index = ProjectPathIndex::scan(CheckoutIdentity::capture(&root).unwrap()).unwrap();
    let [file]: [ProjectPathMatch; 1] = index.search("").unwrap().try_into().unwrap();
    assert_eq!(file.display_path, "inside.md");
    #[cfg(windows)]
    fs::remove_dir(link).unwrap();
    fs::rename(&root, scratch.path().join("retired")).unwrap();
    write_paths(&root, &["substitute.md"]);
    assert!(matches!(index.search(""), Err(FileError::Checkout(_))));
    assert!(matches!(
        index.relative_path(file.id),
        Err(FileError::Checkout(_))
    ));
    let fresh = ProjectPathIndex::scan(CheckoutIdentity::capture(&root).unwrap()).unwrap();
    assert_eq!(labels(&fresh, ""), ["substitute.md"]);
}

#[cfg(any(target_os = "linux", windows))]
#[test]
fn lossy_display_collisions_open_the_distinct_native_paths() {
    use std::ffi::OsString;
    #[cfg(target_os = "linux")]
    let native = {
        use std::os::unix::ffi::OsStringExt;
        OsString::from_vec(b"name-\xff.md".to_vec())
    };
    #[cfg(windows)]
    let native = {
        use std::os::windows::ffi::OsStringExt;
        let units: Vec<_> = "name-\u{fffd}.md"
            .encode_utf16()
            .map(|unit| if unit == 0xfffd { 0xd800 } else { unit })
            .collect();
        OsString::from_wide(&units)
    };
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join(native), b"native").unwrap();
    fs::write(root.path().join("name-\u{fffd}.md"), b"unicode").unwrap();
    let checkout = CheckoutIdentity::capture(root.path()).unwrap();
    let index = ProjectPathIndex::scan(checkout.clone()).unwrap();
    let mut files = CheckoutFiles::new(checkout);
    let items = index.search("name-\u{fffd}.md").unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].display_path, items[1].display_path);
    assert_ne!(items[0].id, items[1].id);
    let contents: BTreeSet<_> = items
        .into_iter()
        .map(|item| {
            let link = files.issue(index.relative_path(item.id).unwrap()).unwrap();
            files.read(link.id).unwrap().bytes
        })
        .collect();
    assert_eq!(
        contents,
        BTreeSet::from([b"native".to_vec(), b"unicode".to_vec()])
    );
}
