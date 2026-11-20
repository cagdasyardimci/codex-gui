use tempfile::tempdir;
use uuid::Uuid;

use super::*;
use crate::storage::drafts::{DraftPatch, DraftRevision, DraftSave, save_draft};

const FIRST: DraftId = DraftId(Uuid::from_u128(1));
const SECOND: DraftId = DraftId(Uuid::from_u128(2));
const IMAGE: &[u8] = b"attachment bytes";

#[test]
fn shared_draft_references_and_leases_protect_the_same_blob() {
    let scratch = tempdir().unwrap();
    let database = scratch.path().join("Workspace café.sqlite3");
    let mut drafts = open_workspace_database(&database).unwrap();
    for draft in [FIRST, SECOND] {
        assert_eq!(
            save_draft(
                &mut drafts,
                draft,
                None,
                DraftRevision::INITIAL,
                &DraftPatch::default()
            )
            .unwrap(),
            DraftSave::Applied
        );
    }

    let store = AttachmentStore::open(&database).unwrap();
    let staged = store.stage(IMAGE).unwrap();
    let id = staged.id();
    let path = staged.path();
    assert_eq!(fs::read(&path).unwrap(), IMAGE);
    let duplicate = store.stage(IMAGE).unwrap();
    assert_eq!(duplicate.id(), id);
    store.replace_draft_references(FIRST, &[id]).unwrap();
    store.replace_draft_references(SECOND, &[id]).unwrap();
    drop(staged);

    store.replace_draft_references(FIRST, &[]).unwrap();
    store.collect().unwrap();
    assert!(path.is_file());
    drop(duplicate);
    store.collect().unwrap();
    assert!(path.is_file());

    let preview = store.lease(id).unwrap();
    store.replace_draft_references(SECOND, &[]).unwrap();
    store.collect().unwrap();
    assert!(preview.path().is_file());
    drop(preview);
    store.collect().unwrap();
    assert!(!path.exists());
    assert!(matches!(store.lease(id), Err(AttachmentError::Missing(_))));
}

#[test]
fn opening_recovers_interrupted_staging_and_unindexed_bytes() {
    let scratch = tempdir().unwrap();
    let database = scratch.path().join("workspace.sqlite3");
    drop(open_workspace_database(&database).unwrap());
    let root = attachment_root(&fs::canonicalize(&database).unwrap());
    let staging = root.join("staging");
    let blobs = root.join("blobs");
    fs::create_dir_all(&staging).unwrap();
    fs::create_dir(&blobs).unwrap();

    let incomplete = staging.join(".partial-interrupted");
    let unrelated = staging.join("unrecognized.txt");
    let promoted = BlobId(Sha256::digest(IMAGE).into()).path(&blobs);
    fs::write(&incomplete, b"partial").unwrap();
    fs::write(&unrelated, b"preserve").unwrap();
    fs::write(&promoted, IMAGE).unwrap();

    let store = AttachmentStore::open(&database).unwrap();
    assert!(!incomplete.exists());
    assert!(!promoted.exists());
    assert_eq!(fs::read(&unrelated).unwrap(), b"preserve");
    let restaged = store.stage(IMAGE).unwrap();
    assert_eq!(fs::read(restaged.path()).unwrap(), IMAGE);
}

#[test]
fn a_lease_keeps_recovery_from_taking_an_active_store() {
    let scratch = tempdir().unwrap();
    let database = scratch.path().join("workspace.sqlite3");
    let store = AttachmentStore::open(&database).unwrap();
    let lease = store.stage(IMAGE).unwrap();
    let path = lease.path();
    drop(store);
    assert!(matches!(
        AttachmentStore::open(&database),
        Err(AttachmentError::Lock(_))
    ));
    assert!(path.exists());
    drop(lease);

    let reopened = AttachmentStore::open(&database).unwrap();
    assert!(!path.exists());
    assert!(reopened.stage(IMAGE).unwrap().path().is_file());
}
