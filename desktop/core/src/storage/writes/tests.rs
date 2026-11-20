use tempfile::tempdir;

use super::*;
use crate::storage::open_workspace_database;

#[test]
fn reservations_order_one_checkout_without_blocking_another_drain() {
    let first_checkout = tempdir().unwrap();
    let second_checkout = tempdir().unwrap();
    let first = CheckoutIdentity::capture(first_checkout.path()).unwrap();
    let second = CheckoutIdentity::capture(second_checkout.path()).unwrap();
    let mut queue = DurableWrites::<&str, &str>::default();

    let first_edit = queue.reserve(&first, "first edit");
    let second_edit = queue.reserve(&first, "second edit");
    let other = queue.reserve(&second, "unrelated edit");
    assert!(matches!(queue.drain(Some(&first)), DrainState::Pending));
    assert_eq!(queue.dispatch_next().unwrap().id, first_edit);
    assert_eq!(queue.dispatch_next().unwrap().id, other);
    assert!(queue.dispatch_next().is_none());
    assert!(!queue.finish(&second, first_edit, Ok(())));
    assert!(queue.finish(&first, first_edit, Ok(())));
    assert_eq!(queue.dispatch_next().unwrap().id, second_edit);
    assert!(queue.finish(&first, second_edit, Ok(())));
    assert!(matches!(queue.drain(Some(&first)), DrainState::Complete));
    assert!(matches!(queue.drain(None), DrainState::Pending));
    assert!(queue.finish(&second, other, Ok(())));
    assert!(matches!(queue.drain(None), DrainState::Complete));
}

#[test]
fn a_failed_sqlite_write_keeps_its_payload_until_a_scoped_retry() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let other_root = tempdir().unwrap();
    let other = CheckoutIdentity::capture(other_root.path()).unwrap();
    let database = open_workspace_database(&scratch.path().join("workspace.sqlite3")).unwrap();
    database
        .execute_batch(
            "CREATE TABLE fixture (message TEXT PRIMARY KEY);
             INSERT INTO fixture VALUES ('café');",
        )
        .unwrap();
    let mut queue = DurableWrites::<String, rusqlite::Error>::default();

    let id = queue.reserve(&checkout, "café".to_string());
    let initial = queue.dispatch_next().unwrap();
    let rejected = database
        .execute(
            "INSERT INTO fixture VALUES (?1)",
            [initial.operation.as_str()],
        )
        .map(|_| ());
    assert!(rejected.is_err());
    assert!(queue.finish(&checkout, id, rejected));
    let later = queue.reserve(&checkout, "another".to_string());
    let independent = queue.dispatch_next().unwrap();
    let outcome = database
        .execute(
            "INSERT INTO fixture VALUES (?1)",
            [independent.operation.as_str()],
        )
        .map(|_| ());
    assert!(outcome.is_ok());
    assert!(queue.finish(&checkout, later, outcome));

    let DrainState::Failed(failures) = queue.drain(Some(&checkout)) else {
        panic!("drain must retain the earlier failed write");
    };
    assert_eq!(failures.len(), 1);
    assert_eq!(failures[0].write.id, id);
    assert_eq!(failures[0].write.operation.as_str(), "café");
    assert!(matches!(
        &failures[0].error,
        rusqlite::Error::SqliteFailure(_, _)
    ));
    assert!(matches!(queue.drain(Some(&other)), DrainState::Complete));
    assert!(queue.retry(&other, id).is_none());

    database
        .execute("DELETE FROM fixture WHERE message = 'café'", [])
        .unwrap();
    let retry = queue.retry(&checkout, id).unwrap();
    let accepted = queue.dispatch_next().unwrap();
    assert_eq!(accepted.id, retry);
    assert_ne!(retry, id);
    assert!(!queue.finish(&checkout, id, Ok(())));
    let outcome = database
        .execute(
            "INSERT INTO fixture VALUES (?1)",
            [accepted.operation.as_str()],
        )
        .map(|_| ());
    assert!(outcome.is_ok());
    assert!(queue.finish(&checkout, retry, outcome));
    assert!(matches!(queue.drain(None), DrainState::Complete));
}
