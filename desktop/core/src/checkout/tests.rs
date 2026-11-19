use tempfile::tempdir;

use super::*;

#[test]
fn validates_native_paths_with_spaces_unicode_and_alias_components() {
    let container = tempdir().unwrap();
    let checkout = container.path().join("project café");
    fs::create_dir(&checkout).unwrap();
    let alias = checkout.join("..").join("project café");

    let captured = CheckoutIdentity::capture(&checkout).unwrap();

    assert_eq!(CheckoutIdentity::capture(&alias).unwrap(), captured);
    captured.validate_reported(&alias).unwrap();

    #[cfg(windows)]
    assert!(matches!(
        captured.canonical_path().components().next(),
        Some(std::path::Component::Prefix(_))
    ));
}

#[cfg(unix)]
#[test]
fn symlink_aliases_resolve_to_the_same_checkout() {
    let container = tempdir().unwrap();
    let checkout = container.path().join("checkout");
    fs::create_dir(&checkout).unwrap();
    let alias = container.path().join("alias");
    std::os::unix::fs::symlink(&checkout, &alias).unwrap();

    let captured = CheckoutIdentity::capture(&checkout).unwrap();
    assert_eq!(CheckoutIdentity::capture(&alias).unwrap(), captured);
    captured.validate_reported(&alias).unwrap();
}

#[test]
fn rejects_a_backend_checkout_outside_the_captured_root() {
    let checkout = tempdir().unwrap();
    let foreign = tempdir().unwrap();
    let captured = CheckoutIdentity::capture(checkout.path()).unwrap();

    assert!(matches!(
        captured.validate_reported(foreign.path()),
        Err(CheckoutError::Mismatch { .. })
    ));
    assert!(matches!(
        captured.validate_reported(Path::new("relative")),
        Err(CheckoutError::Relative(_))
    ));
}

#[test]
fn replacing_the_directory_at_the_same_path_invalidates_the_old_identity() {
    let container = tempdir().unwrap();
    let checkout = container.path().join("checkout");
    fs::create_dir(&checkout).unwrap();
    let captured = CheckoutIdentity::capture(&checkout).unwrap();
    fs::rename(&checkout, container.path().join("retired")).unwrap();
    fs::create_dir(&checkout).unwrap();

    assert_ne!(CheckoutIdentity::capture(&checkout).unwrap(), captured);
    assert!(matches!(
        captured.revalidate(),
        Err(CheckoutError::Replaced(_))
    ));
}
