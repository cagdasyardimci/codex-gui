use std::path::{Path, PathBuf};

use tempfile::tempdir;

use super::*;
use crate::{
    identity::{RequestId, ThreadId},
    storage::{
        attachments::{AttachmentStore, JournalEntry, JournalPhase},
        drafts::{DraftId, DraftRevision, read_draft},
        open_workspace_database,
    },
    workspace::WorkspaceEngine,
};

const SAME_TEXT: &str = "identical prompt";

fn seed(path: &Path, checkout: &CheckoutIdentity, index: u128, dispatched: bool) -> PathBuf {
    let store = AttachmentStore::open(path).unwrap();
    let draft = DraftId(Uuid::from_u128(index));
    let thread = ThreadId(format!("thread-{index}"));
    let id = RequestId(draft.0);
    let attachment = [store.stage(index.to_string().as_bytes()).unwrap()];
    store
        .bind_thread_draft(
            &thread,
            draft,
            DraftRevision::INITIAL,
            SAME_TEXT,
            &[],
            &attachment,
        )
        .unwrap();
    let write = store.reserve_submission(JournalEntry {
        id,
        thread: &thread,
        draft,
        revision: DraftRevision::INITIAL,
        request: &json!({"cwd": checkout.canonical_path(), "clientUserMessageId": id.0.to_string()}),
        attachments: &attachment,
        checkout,
        queue_add: false,
    }).unwrap();
    if dispatched {
        store
            .set_submission_phase(id, JournalPhase::Dispatching)
            .unwrap();
    }
    assert!(
        !store
            .pending_submissions(checkout)
            .unwrap()
            .iter()
            .any(|entry| entry.id == id)
    );
    drop(write);
    attachment[0].path()
}

#[tokio::test]
async fn restart_recovers_only_exact_unambiguous_history_and_never_replays() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let path = scratch.path().join("workspace.sqlite3");
    seed(&path, &checkout, 1, false);
    let accepted_blob = seed(&path, &checkout, 2, true);
    let uncertain_blob = seed(&path, &checkout, 3, true);
    seed(&path, &checkout, 4, true);
    let store = AttachmentStore::open(&path).unwrap();
    let (transport, server_in, mut replies) = transport_for(4096, 2, Some(checkout.clone()));
    let client = &transport.client;
    let (engine, _effects) = WorkspaceEngine::start(client.identity().clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let (recovery, ()) = time::timeout(DEADLINE, async {
        tokio::join!(engine.recover_submissions(client, &store, DEADLINE), async {
            for index in [2, 3, 4] {
                let thread = format!("thread-{index}");
                let summary = next_request(&mut server).await;
                assert_eq!(summary["method"], "thread/read");
                assert_eq!(summary["params"], json!({"threadId":thread, "includeTurns":false}));
                respond(&mut replies, summary["id"].clone(), json!({
                    "thread": {"id":thread,"cwd":checkout.canonical_path(),"preview":"","createdAt":0,"updatedAt":0,"status":{"type":"idle"}}
                })).await;

                let full = next_request(&mut server).await;
                assert_eq!(full["method"], "thread/turns/list");
                assert_eq!(full["params"]["threadId"], thread);
                assert_eq!(full["params"]["itemsView"], "full");
                let unrelated = item("other-turn", (index == 4).then_some(Uuid::from_u128(4)));
                let more = index != 3;
                respond(&mut replies, full["id"].clone(), json!({
                    "data":[unrelated],"nextCursor":more.then_some("older")
                })).await;
                if more {
                    let older = next_request(&mut server).await;
                    assert_eq!(older["method"], "thread/turns/list");
                    assert_eq!(older["params"]["cursor"], "older");
                    respond(&mut replies, older["id"].clone(), json!({
                        "data":[item("exact-turn", Some(Uuid::from_u128(index)))],"nextCursor":null
                    })).await;
                }
            }
        })
    }).await.unwrap();
    let recovery = recovery.unwrap();
    let id = |index| RequestId(Uuid::from_u128(index));
    assert_eq!(recovery.unsent, [id(1)]);
    assert_eq!(recovery.acknowledged, [id(2)]);
    assert_eq!(recovery.unresolved, [id(3), id(4)]);
    let db = open_workspace_database(&path).unwrap();
    let states: Vec<(String, Option<String>, i64)> = db.prepare(
        "SELECT phase, o.turn_id, (SELECT COUNT(*) FROM submission_attachments WHERE submission_id = s.id)
         FROM submissions s LEFT JOIN submission_outcomes o ON s.id = o.id ORDER BY s.id",
    ).unwrap().query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?))).unwrap()
        .collect::<rusqlite::Result<_>>().unwrap();
    assert_eq!(
        states,
        [
            ("unsent".into(), None, 0),
            ("dispatching".into(), Some("exact-turn".into()), 0),
            ("dispatching".into(), None, 1),
            ("dispatching".into(), None, 1),
        ]
    );
    for index in [1, 2, 3, 4] {
        let draft = read_draft(&db, DraftId(id(index).0)).unwrap().unwrap();
        assert_eq!(draft.text, if index == 2 { "" } else { SAME_TEXT });
    }
    store.collect().unwrap();
    assert!(accepted_blob.is_file());
    assert!(uncertain_blob.is_file());
    assert!(
        time::timeout(Duration::from_millis(50), server.next_frame())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn a_replaced_checkout_does_not_recover_the_previous_directorys_submission() {
    let scratch = tempdir().unwrap();
    let directory = scratch.path().join("project");
    std::fs::create_dir(&directory).unwrap();
    let previous = CheckoutIdentity::capture(&directory).unwrap();
    let path = scratch.path().join("workspace.sqlite3");
    seed(&path, &previous, 1, true);
    std::fs::rename(&directory, scratch.path().join("previous")).unwrap();
    std::fs::create_dir(&directory).unwrap();
    let replacement = CheckoutIdentity::capture(&directory).unwrap();
    let (transport, _, _replies) = transport_for(4096, 2, Some(replacement));
    let client = &transport.client;
    let (engine, _effects) = WorkspaceEngine::start(client.identity().clone());
    let store = AttachmentStore::open(&path).unwrap();
    let recovered = engine
        .recover_submissions(client, &store, DEADLINE)
        .await
        .unwrap();
    assert_eq!(recovered.unresolved, [RequestId(Uuid::from_u128(1))]);
    assert!(recovered.acknowledged.is_empty());
}

fn item(turn: &str, client: Option<Uuid>) -> Value {
    json!({"id":turn,"status":"completed","items":[
        {"type":"userMessage","id":format!("message-{turn}"),"clientId":client.map(|id| id.to_string()),
         "content":[{"type":"text","text":SAME_TEXT}]}
    ]})
}
