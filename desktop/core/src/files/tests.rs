use std::fs;

use super::*;

#[test]
fn reads_by_scoped_handle_and_detects_replacement() {
    let root = tempfile::tempdir().unwrap();
    let relative = Path::new("code").join("source.txt");
    let target = root.path().join(&relative);
    fs::create_dir(target.parent().unwrap()).unwrap();
    fs::write(&target, "original λ").unwrap();
    let checkout = CheckoutIdentity::capture(root.path()).unwrap();
    let mut files = CheckoutFiles::new(checkout.clone());
    let other = CheckoutFiles::new(checkout);
    let link = files.issue(&relative).unwrap();
    let encoded = serde_json::to_value(&link).unwrap();
    assert_eq!(encoded["displayPath"], relative.to_str().unwrap());
    let id: FileHandle = serde_json::from_value(encoded["id"].clone()).unwrap();
    assert!(matches!(other.read(id), Err(FileError::InvalidHandle)));

    let initial = files.read(id).unwrap();
    assert_eq!(initial.bytes, "original λ".as_bytes());
    assert_eq!(initial.revision.byte_count, initial.bytes.len());
    assert_eq!(
        initial.revision.digest,
        hex::encode(Sha256::digest(&initial.bytes))
    );
    fs::write(&target, "external edit").unwrap();
    let edited = files.read(id).unwrap();
    assert_eq!(edited.bytes, b"external edit");
    assert_ne!(edited.revision, initial.revision);

    fs::rename(&target, target.with_extension("old")).unwrap();
    fs::write(&target, "different file").unwrap();
    assert!(matches!(files.read(id), Err(FileError::Replaced)));
    files.close(id);
    assert!(matches!(files.read(id), Err(FileError::InvalidHandle)));
}

#[test]
fn rejects_invalid_paths_retired_checkouts_and_oversized_reads() {
    let parent = tempfile::tempdir().unwrap();
    let root = parent.path().join("checkout");
    fs::create_dir(&root).unwrap();
    let target = root.join("large");
    let file = File::create(&target).unwrap();
    file.set_len(MAX_READ_BYTES + 1).unwrap();
    drop(file);
    let mut files = CheckoutFiles::new(CheckoutIdentity::capture(&root).unwrap());
    for invalid in [
        target.as_path(),
        Path::new("../outside"),
        Path::new(""),
        Path::new("."),
    ] {
        assert!(matches!(files.issue(invalid), Err(FileError::InvalidPath)));
    }
    let link = files.issue(Path::new("large")).unwrap();
    assert!(matches!(files.read(link.id), Err(FileError::TooLarge)));

    fs::rename(&root, parent.path().join("old")).unwrap();
    fs::create_dir(&root).unwrap();
    fs::write(&target, "replacement").unwrap();
    assert!(matches!(
        files.read(link.id),
        Err(FileError::Checkout(CheckoutError::Replaced(_)))
    ));
}

#[cfg(unix)]
#[test]
fn rejects_links_inside_and_outside_the_checkout() {
    use std::os::unix::fs::symlink;

    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(root.path().join("source.txt"), "inside").unwrap();
    fs::write(outside.path().join("source.txt"), "outside").unwrap();
    symlink("source.txt", root.path().join("alias")).unwrap();
    symlink(outside.path(), root.path().join("directory-link")).unwrap();
    let mut files = CheckoutFiles::new(CheckoutIdentity::capture(root.path()).unwrap());
    assert!(files.issue(Path::new("alias")).is_err());
    assert!(files.issue(Path::new("directory-link/source.txt")).is_err());

    let link = files.issue(Path::new("source.txt")).unwrap();
    fs::rename(root.path().join("source.txt"), root.path().join("prior")).unwrap();
    symlink(
        outside.path().join("source.txt"),
        root.path().join("source.txt"),
    )
    .unwrap();
    assert!(files.read(link.id).is_err());
}

#[cfg(windows)]
#[test]
fn rejects_junctions_and_alternate_streams() {
    use std::process::Command;

    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("source.txt"), "outside").unwrap();
    let junction = root.path().join("junction");
    let result = Command::new("cmd.exe")
        .args(["/d", "/c", "mklink", "/J"])
        .arg(&junction)
        .arg(outside.path())
        .output()
        .unwrap();
    assert!(result.status.success(), "{result:?}");
    let mut files = CheckoutFiles::new(CheckoutIdentity::capture(root.path()).unwrap());
    let inaccessible = files.issue(&Path::new("junction").join("source.txt"));
    fs::remove_dir(&junction).unwrap();
    assert!(inaccessible.is_err());

    let target = root.path().join("file.txt");
    fs::write(&target, "default stream").unwrap();
    fs::write(root.path().join("file.txt:hidden"), "alternate stream").unwrap();
    assert!(files.issue(Path::new("file.txt:hidden")).is_err());
}

#[test]
#[cfg(any(target_os = "linux", windows))]
fn display_collisions_keep_distinct_native_names() {
    use std::ffi::OsString;

    #[cfg(target_os = "linux")]
    let native_name = {
        use std::os::unix::ffi::OsStringExt;
        OsString::from_vec(b"name-\xff.txt".to_vec())
    };
    #[cfg(windows)]
    let native_name = {
        use std::os::windows::ffi::OsStringExt;
        let units: Vec<_> = "name-"
            .encode_utf16()
            .chain([0xd800])
            .chain(".txt".encode_utf16())
            .collect();
        OsString::from_wide(&units)
    };
    let root = tempfile::tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(root.path()).unwrap();
    let display_name = native_name.to_string_lossy().into_owned();
    let native_path = Path::new(&native_name);
    let display_path = Path::new(&display_name);
    fs::write(checkout.canonical_path().join(native_path), "native").unwrap();
    fs::write(checkout.canonical_path().join(display_path), "display").unwrap();
    let mut files = CheckoutFiles::new(checkout);
    let native = files.issue(native_path).unwrap();
    let display = files.issue(display_path).unwrap();
    assert_eq!(native.display_path, display.display_path);
    assert_ne!(native.id, display.id);
    assert_eq!(files.read(native.id).unwrap().bytes, b"native");
    assert_eq!(files.read(display.id).unwrap().bytes, b"display");
}
