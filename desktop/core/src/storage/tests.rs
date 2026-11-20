use std::{sync::Barrier, thread};

use tempfile::tempdir;

use super::*;

fn metadata(database: &Connection) -> (i32, i32, bool) {
    let application = database
        .pragma_query_value(None, "application_id", |row| row.get(0))
        .unwrap();
    let version = database
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .unwrap();
    let foreign_keys = database
        .pragma_query_value(None, "foreign_keys", |row| row.get(0))
        .unwrap();
    (application, version, foreign_keys)
}

#[test]
fn fresh_database_is_claimed_once_when_two_openers_race() {
    let scratch = tempdir().unwrap();
    let path = scratch.path().join("Workspace café.sqlite3");
    let start = Barrier::new(2);

    thread::scope(|scope| {
        let open = || {
            start.wait();
            let database = open_workspace_database(&path).unwrap();
            assert_eq!(metadata(&database), (APPLICATION_ID, 1, true));
        };
        let first = scope.spawn(open);
        let second = scope.spawn(open);
        first.join().unwrap();
        second.join().unwrap();
    });

    let reopened = open_workspace_database(&path).unwrap();
    assert_eq!(metadata(&reopened), (APPLICATION_ID, 1, true));
}

#[test]
fn migrating_an_older_test_database_preserves_its_records() {
    let scratch = tempdir().unwrap();
    let path = scratch.path().join("version-zero.sqlite3");
    let old = Connection::open(&path).unwrap();
    old.pragma_update(None, "application_id", APPLICATION_ID)
        .unwrap();
    old.execute_batch(
        "CREATE TABLE saved_fixture (value TEXT NOT NULL);
         INSERT INTO saved_fixture (value) VALUES ('preserve café');",
    )
    .unwrap();
    drop(old);

    let database = open_workspace_database(&path).unwrap();
    assert_eq!(metadata(&database), (APPLICATION_ID, 1, true));
    drop(database);

    let reopened = open_workspace_database(&path).unwrap();
    let value: String = reopened
        .query_row("SELECT value FROM saved_fixture", [], |row| row.get(0))
        .unwrap();
    assert_eq!(value, "preserve café");
}

#[test]
fn incompatible_databases_keep_their_version_and_identity() {
    let scratch = tempdir().unwrap();
    let foreign = scratch.path().join("other-app.sqlite3");
    let database = Connection::open(&foreign).unwrap();
    database
        .execute_batch("CREATE TABLE other_application (value TEXT);")
        .unwrap();
    drop(database);

    assert!(matches!(
        open_workspace_database(&foreign),
        Err(DatabaseOpenError::ForeignDatabase)
    ));
    let untouched = Connection::open(&foreign).unwrap();
    assert_eq!(metadata(&untouched).0, 0);
    assert_eq!(metadata(&untouched).1, 0);

    let future = scratch.path().join("future.sqlite3");
    let database = open_workspace_database(&future).unwrap();
    database.pragma_update(None, "user_version", 99).unwrap();
    drop(database);
    assert!(matches!(
        open_workspace_database(&future),
        Err(DatabaseOpenError::UnsupportedSchema(99))
    ));
    assert_eq!(metadata(&Connection::open(&future).unwrap()).1, 99);
}
