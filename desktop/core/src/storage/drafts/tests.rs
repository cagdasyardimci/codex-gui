use serde_json::json;
use tempfile::tempdir;

use super::*;
use crate::storage::open_workspace_database;

const DRAFT: DraftId = DraftId(Uuid::from_u128(1));

#[test]
fn updates_only_changed_fields_and_reopens_the_complete_draft() {
    let scratch = tempdir().unwrap();
    let path = scratch.path().join("drafts.sqlite3");
    let initial_context = vec![json!({"type": "file", "path": "Project café.txt"})];
    let mut storage = open_workspace_database(&path).unwrap();
    assert_eq!(
        save_draft(
            &mut storage,
            DRAFT,
            None,
            DraftRevision::INITIAL,
            &DraftPatch {
                text: Some("old text".into()),
                context: Some(initial_context.clone()),
            },
        )
        .unwrap(),
        DraftSave::Applied
    );
    storage
        .execute_batch(
            "CREATE TEMP TABLE context_writes (id BLOB);
             CREATE TEMP TRIGGER audit_context AFTER UPDATE OF context ON drafts BEGIN
                INSERT INTO context_writes VALUES (new.id);
             END;",
        )
        .unwrap();

    let revision = DraftRevision::INITIAL.next().unwrap();
    assert_eq!(
        save_draft(
            &mut storage,
            DRAFT,
            Some(DraftRevision::INITIAL),
            revision,
            &DraftPatch {
                text: Some("updated 🍵".into()),
                context: Some(initial_context.clone()),
            },
        )
        .unwrap(),
        DraftSave::Applied
    );
    let context_updates: i64 = storage
        .query_row("SELECT count(*) FROM context_writes", [], |row| row.get(0))
        .unwrap();
    assert_eq!(context_updates, 0);
    drop(storage);

    let storage = open_workspace_database(&path).unwrap();
    assert_eq!(
        read_draft(&storage, DRAFT).unwrap(),
        Some(StoredDraft {
            revision,
            text: "updated 🍵".into(),
            context: initial_context,
        })
    );
}

#[test]
fn an_accepted_edit_from_another_connection_retires_a_stale_patch() {
    let scratch = tempdir().unwrap();
    let path = scratch.path().join("drafts.sqlite3");
    let mut first = open_workspace_database(&path).unwrap();
    let mut second = open_workspace_database(&path).unwrap();
    let base = DraftRevision::INITIAL;
    let winner = base.next().unwrap();
    assert_eq!(
        save_draft(&mut first, DRAFT, None, base, &DraftPatch::default()).unwrap(),
        DraftSave::Applied
    );
    let winner_patch = DraftPatch {
        text: Some("kept".into()),
        context: Some(vec![json!({"type": "file", "path": "tracked.txt"})]),
    };
    assert_eq!(
        save_draft(&mut first, DRAFT, Some(base), winner, &winner_patch).unwrap(),
        DraftSave::Applied
    );
    let stale = DraftPatch {
        text: Some("stale".into()),
        context: Some(Vec::new()),
    };
    assert_eq!(
        save_draft(
            &mut second,
            DRAFT,
            Some(base),
            winner.next().unwrap(),
            &stale
        )
        .unwrap(),
        DraftSave::Stale {
            current: Some(winner)
        }
    );
    assert_eq!(
        read_draft(&second, DRAFT).unwrap(),
        Some(StoredDraft {
            revision: winner,
            text: winner_patch.text.unwrap(),
            context: winner_patch.context.unwrap(),
        })
    );
}
