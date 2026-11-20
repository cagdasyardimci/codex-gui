use tempfile::{TempDir, tempdir};

use super::*;
use crate::{
    identity::{OperationIdentity, RequestId, ThreadId, TurnId},
    storage::{
        attachments::{AttachmentStore, JournalError},
        drafts::{DraftId, DraftPatch, DraftRevision, DraftSave, read_draft, save_draft},
        open_workspace_database,
    },
    workspace::{
        ExecutionTarget, PreparedThread, SendDraft, SendIntent, SendSettings,
        SubmissionAcknowledgement, SubmissionError, WorkspaceAction, WorkspaceEngine,
        WorkspaceError,
    },
};

struct Fixture {
    checkout: CheckoutIdentity,
    scratch: TempDir,
    store: AttachmentStore,
    transport: Transport,
    engine: WorkspaceEngine,
    server: JsonlReader<ReadHalf<DuplexStream>>,
    replies: WriteHalf<DuplexStream>,
}

#[path = "queue_edit.rs"]
mod queue_edit;

impl Fixture {
    async fn prepared() -> (
        Self,
        PreparedThread,
        OperationIdentity,
        DraftId,
        std::path::PathBuf,
    ) {
        let scratch = tempdir().unwrap();
        let checkout_path = scratch.path().join("checkout");
        std::fs::create_dir(&checkout_path).unwrap();
        let checkout = CheckoutIdentity::capture(&checkout_path).unwrap();
        let store = AttachmentStore::open(&scratch.path().join("workspace.sqlite3")).unwrap();
        let lease = store.stage(&b"test image"[..]).unwrap();
        let attachment_path = lease.path();
        let (transport, server_in, mut replies) = transport_for(128, 1, Some(checkout.clone()));
        let client = &transport.client;
        let (engine, mut effects) = WorkspaceEngine::start(client.identity().clone());
        let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
        let operation = OperationIdentity {
            connection: client.identity().clone(),
            request: RequestId(Uuid::from_u128(42)),
        };
        let draft = DraftId(Uuid::from_u128(43));
        engine
            .apply(WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
                operation: operation.clone(),
                draft: SendDraft {
                    id: draft,
                    revision: DraftRevision::INITIAL,
                    text: "  café\n".into(),
                    context: Vec::new(),
                    attachments: vec![lease],
                },
                settings: SendSettings {
                    model: Some("fixture-model".into()),
                    reasoning_effort: Some("high".into()),
                    service_tier: Some("fast".into()),
                    ..SendSettings::default()
                },
            })))
            .await
            .unwrap();
        let effect = effects.try_recv().unwrap();
        let (prepared, ()) = time::timeout(DEADLINE, async {
            tokio::join!(
                engine.prepare_thread(effect, client, &store, DEADLINE),
                async {
                    let request = next_request(&mut server).await;
                    assert_eq!(request["method"], "thread/start");
                    let cwd = checkout.canonical_path();
                    respond(
                        &mut replies,
                        request["id"].clone(),
                        json!({
                            "cwd": cwd, "thread": { "id": "thread-1", "cwd": cwd }
                        }),
                    )
                    .await;
                }
            )
        })
        .await
        .unwrap();
        (
            Self {
                checkout,
                scratch,
                store,
                transport,
                engine,
                server,
                replies,
            },
            prepared.unwrap(),
            operation,
            draft,
            attachment_path,
        )
    }

    fn queue_intent(&self, draft: DraftId, id: u128) -> Arc<SendIntent> {
        Arc::new(SendIntent {
            operation: OperationIdentity {
                connection: self.transport.client.identity().clone(),
                request: RequestId(Uuid::from_u128(id)),
            },
            draft: SendDraft {
                id: draft,
                revision: DraftRevision::INITIAL,
                text: "  café\n".into(),
                context: Vec::new(),
                attachments: vec![self.store.stage(&b"test image"[..]).unwrap()],
            },
            settings: SendSettings {
                model: Some("captured-model".into()),
                ..SendSettings::default()
            },
        })
    }
}

fn queue_target() -> ExecutionTarget {
    ExecutionTarget {
        thread: ThreadId("thread-1".into()),
        turn: TurnId("active-turn".into()),
    }
}

fn active_turn_event(method: &str, status: &str) -> ServerEvent {
    ServerEvent::Notification {
        method: method.into(),
        params: json!({"threadId":"thread-1", "turn":{"id":"active-turn","status":status}}),
    }
}

#[tokio::test]
async fn queue_add_requires_its_active_turn_and_keeps_newer_typing() {
    let (mut fixture, _prepared, _, draft, attachment) = Fixture::prepared().await;
    let client = &fixture.transport.client;
    let engine = &fixture.engine;
    let store = &fixture.store;
    let intent = fixture.queue_intent(draft, 80);
    let mut db =
        open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
    assert!(matches!(
        engine
            .enqueue_follow_up(intent.clone(), queue_target(), client, store, DEADLINE)
            .await,
        Err(SubmissionError::Workspace(WorkspaceError::InactiveTurn))
    ));
    engine
        .observe_execution_event(
            client.identity(),
            &active_turn_event("turn/started", "inProgress"),
        )
        .await
        .unwrap();
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.enqueue_follow_up(intent.clone(), queue_target(), client, store, DEADLINE),
            async {
                let outgoing = next_request(&mut fixture.server).await;
                assert_eq!(outgoing["method"], "thread/queue/add");
                let client_id = intent.operation.request.0.to_string();
                assert_eq!(outgoing["params"], json!({
                    "threadId":"thread-1", "clientUserMessageId": client_id,
                    "input":[{"type":"text","text":"  café\n"},{"type":"localImage","path":attachment}]
                }));
                let journaled: String = db.query_row(
                    "SELECT request FROM submissions JOIN queue_receipts USING (id) WHERE phase = 'dispatching'",
                    [], |row| row.get(0),
                ).unwrap();
                assert_eq!(serde_json::from_str::<Value>(&journaled).unwrap()["model"], "captured-model");
                assert_eq!(
                    save_draft(&mut db, draft, Some(DraftRevision::INITIAL), DraftRevision::INITIAL.next().unwrap(),
                        &DraftPatch { text: Some("already typing the next draft".into()), context: None }).unwrap(),
                    DraftSave::Applied,
                );
                respond(&mut fixture.replies, outgoing["id"].clone(), json!({
                    "queuedSubmission":{"id":"queued-80","clientUserMessageId":client_id,"input":outgoing["params"]["input"]}
                })).await;
            }
        )
    }).await.unwrap();
    assert_eq!(
        reply.unwrap().acknowledgement,
        SubmissionAcknowledgement::Queued {
            retired_draft: false
        }
    );
    assert_eq!(
        read_draft(&db, draft).unwrap().unwrap().text,
        "already typing the next draft"
    );
    assert!(
        !store
            .has_unresolved_submission(&fixture.checkout, draft)
            .unwrap()
    );
    assert!(
        time::timeout(Duration::from_millis(50), fixture.server.next_frame())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn a_lost_queue_reply_recovers_the_receipt_then_consumption_moves_attachment_ownership() {
    let (mut fixture, prepared, _, draft, attachment) = Fixture::prepared().await;
    drop(prepared);
    let path = fixture.scratch.path().join("workspace.sqlite3");
    let intent = fixture.queue_intent(draft, 81);
    let request = intent.operation.request;
    let duplicate = fixture.queue_intent(draft, 82);
    let client = &fixture.transport.client;
    let engine = &fixture.engine;
    let store = &fixture.store;
    let client_id = request.0.to_string();
    engine
        .observe_execution_event(
            client.identity(),
            &active_turn_event("turn/started", "inProgress"),
        )
        .await
        .unwrap();
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.enqueue_follow_up(intent, queue_target(), client, store, DEADLINE),
            async {
                let outgoing = next_request(&mut fixture.server).await;
                assert_eq!(outgoing["method"], "thread/queue/add");
                assert_eq!(outgoing["params"]["clientUserMessageId"], client_id);
                assert!(matches!(
                    engine
                        .enqueue_follow_up(duplicate, queue_target(), client, store, DEADLINE)
                        .await,
                    Err(SubmissionError::Journal(JournalError::PendingDraft))
                ));
                // The server received the add. The active turn completes before its add reply reaches the client.
                engine
                    .observe_execution_event(
                        client.identity(),
                        &active_turn_event("turn/completed", "completed"),
                    )
                    .await
                    .unwrap();
            }
        )
    })
    .await
    .unwrap();
    assert!(matches!(
        reply.unwrap().response,
        Err(RequestError::Stopped(Delivery::PossiblySent))
    ));
    assert!(
        store
            .has_unresolved_submission(&fixture.checkout, draft)
            .unwrap()
    );

    let Fixture {
        checkout,
        scratch: _scratch,
        store,
        ..
    } = fixture;
    drop(store);
    let store = AttachmentStore::open(&path).unwrap();
    let (transport, server_in, mut replies) = transport_for(4096, 2, Some(checkout.clone()));
    let client = &transport.client;
    let (engine, _effects) = WorkspaceEngine::start(client.identity().clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let db = open_workspace_database(&path).unwrap();
    assert_eq!(read_draft(&db, draft).unwrap().unwrap().text, "  café\n");
    let ownership = || -> (i64, i64) {
        db.query_row(
            "SELECT (SELECT count(*) FROM submission_attachments), (SELECT count(*) FROM sent_submission_attachments)",
            [], |row| Ok((row.get(0)?, row.get(1)?)),
        ).unwrap()
    };
    for queued in [true, false] {
        let (recovery, ()) = time::timeout(DEADLINE, async {
            tokio::join!(engine.recover_submissions(client, &store, DEADLINE), async {
                let summary = next_request(&mut server).await;
                assert_eq!(summary["method"], "thread/read");
                assert_eq!(summary["params"], json!({"threadId":"thread-1","includeTurns":false}));
                respond(&mut replies, summary["id"].clone(), json!({
                    "thread":{"id":"thread-1","cwd":checkout.canonical_path(),"preview":"","createdAt":0,"updatedAt":0,"status":{"type":"idle"}}
                })).await;
                let list = next_request(&mut server).await;
                assert_eq!(list["method"], "thread/queue/list");
                assert_eq!(list["params"]["threadId"], "thread-1");
                let data = if queued {
                    vec![json!({"id":"queued-81","clientUserMessageId":client_id,"input":[{"type":"text","text":"  café\n"}]})]
                } else {
                    Vec::new()
                };
                respond(&mut replies, list["id"].clone(), json!({"data":data,"nextCursor":null})).await;
                if !queued {
                    let history = next_request(&mut server).await;
                    assert_eq!(history["method"], "thread/turns/list");
                    assert_eq!(history["params"]["threadId"], "thread-1");
                    respond(&mut replies, history["id"].clone(), json!({
                        "data":[{"id":"consuming-turn","status":"completed","items":[
                            {"type":"userMessage","id":"consumed","clientId":client_id,"content":[]}
                        ]}],"nextCursor":null
                    })).await;
                }
            })
        }).await.unwrap();
        let recovery = recovery.unwrap();
        assert_eq!(recovery.acknowledged, [request]);
        assert!(recovery.unresolved.is_empty());
        assert!(!store.has_unresolved_submission(&checkout, draft).unwrap());
        assert_eq!(read_draft(&db, draft).unwrap().unwrap().text, "");
        assert_eq!(ownership(), if queued { (1, 0) } else { (0, 1) });
        store.collect().unwrap();
        assert!(attachment.is_file());
    }
    assert!(
        time::timeout(Duration::from_millis(50), server.next_frame())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn first_turn_writes_the_exact_journaled_request_from_a_non_git_checkout() {
    let (mut fixture, prepared, operation, draft, attachment) = Fixture::prepared().await;
    let mut database =
        open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
    assert!(!fixture.checkout.canonical_path().join(".git").exists());
    let engine = &fixture.engine;
    let client = &fixture.transport.client;
    let store = &fixture.store;
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(engine.submit_prepared(prepared, client, store, DEADLINE), async {
            let outgoing = next_request(&mut fixture.server).await;
            assert_eq!(outgoing["method"], "turn/start");
            let (request, phase, edges): (String, String, i64) = database.query_row(
                "SELECT request, phase, (
                     SELECT COUNT(*) FROM submission_attachments WHERE submission_id = submissions.id
                 ) FROM submissions WHERE id = ?1",
                [operation.request.0.as_bytes().as_slice()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            ).unwrap();
            assert_eq!(phase, "dispatching");
            assert_eq!(edges, 1);
            assert_eq!(serde_json::from_str::<Value>(&request).unwrap(), outgoing["params"]);
            assert_eq!(outgoing["params"]["clientUserMessageId"], operation.request.0.to_string());
            assert_eq!(outgoing["params"]["cwd"], json!(fixture.checkout.canonical_path()));
            assert_eq!(outgoing["params"]["threadId"], "thread-1");
            assert_eq!(outgoing["params"]["input"], json!([
                {"type": "text", "text": "  café\n"},
                {"type": "localImage", "path": attachment},
            ]));
            assert_eq!(outgoing["params"]["model"], "fixture-model");
            assert_eq!(outgoing["params"]["effort"], "high");
            assert_eq!(outgoing["params"]["serviceTierForTurn"], "fast");
            respond(&mut fixture.replies, outgoing["id"].clone(), json!({"turn": {"id": "turn-1"}})).await;
        })
    }).await.unwrap();
    let reply = reply.unwrap();
    assert_eq!(reply.operation, operation);
    assert_eq!(
        reply.acknowledgement,
        SubmissionAcknowledgement::Accepted {
            retired_draft: true
        }
    );
    assert_eq!(reply.response.unwrap()["turn"]["id"], "turn-1");
    let retired = read_draft(&database, draft).unwrap().unwrap();
    assert_eq!(retired.text, "");
    assert_eq!(retired.revision, DraftRevision::INITIAL);
    assert_eq!(
        save_draft(
            &mut database,
            draft,
            Some(DraftRevision::INITIAL),
            DraftRevision::INITIAL.next().unwrap(),
            &DraftPatch {
                text: Some("debounced next edit".into()),
                context: None
            },
        )
        .unwrap(),
        DraftSave::Applied
    );
    assert_eq!(
        read_draft(&database, draft).unwrap().unwrap().text,
        "debounced next edit"
    );
    store.collect().unwrap();
    assert!(attachment.is_file());
}

#[tokio::test]
async fn an_exact_item_event_before_the_reply_retires_once_and_keeps_newer_draft_edits() {
    let (mut fixture, prepared, operation, draft, attachment) = Fixture::prepared().await;
    let mut db =
        open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
    let client = &fixture.transport.client;
    let inbox = &mut fixture.transport.inbox;
    let engine = &fixture.engine;
    let store = &fixture.store;
    let next_revision = DraftRevision::INITIAL.next().unwrap();
    let new_attachment = store.stage(&b"replacement image"[..]).unwrap();
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.submit_prepared(prepared, client, store, DEADLINE),
            async {
                let outgoing = next_request(&mut fixture.server).await;
                save_draft(
                    &mut db,
                    draft,
                    Some(DraftRevision::INITIAL),
                    next_revision,
                    &DraftPatch {
                        text: Some("new draft".into()),
                        context: Some(vec![json!("new context")]),
                    },
                )
                .unwrap();
                store
                    .replace_draft_references(draft, &[new_attachment.id()])
                    .unwrap();

                for (client_id, expected) in [
                    (
                        Uuid::from_u128(404).to_string(),
                        SubmissionAcknowledgement::Unmatched,
                    ),
                    (
                        operation.request.0.to_string(),
                        SubmissionAcknowledgement::Accepted {
                            retired_draft: false,
                        },
                    ),
                ] {
                    let event = encode_frame(&json!({
                        "method": "item/started",
                        "params": {
                            "threadId": "thread-1", "turnId": "turn-1",
                            "item": { "type": "userMessage", "id": "item-1", "clientId": client_id }
                        }
                    }))
                    .unwrap();
                    fixture.replies.write_all(&event).await.unwrap();
                    let event = inbox.recv().await.unwrap();
                    assert_eq!(
                        engine
                            .observe_submission_event(client.identity(), &event, store)
                            .await
                            .unwrap(),
                        expected
                    );
                }
                respond(
                    &mut fixture.replies,
                    outgoing["id"].clone(),
                    json!({"turn": {"id": "turn-1"}}),
                )
                .await;
            }
        )
    })
    .await
    .unwrap();
    assert_eq!(
        reply.unwrap().acknowledgement,
        SubmissionAcknowledgement::Duplicate
    );
    let saved = read_draft(&db, draft).unwrap().unwrap();
    assert_eq!(saved.revision, next_revision);
    assert_eq!(saved.text, "new draft");
    assert_eq!(saved.context, [json!("new context")]);
    let sent: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM sent_submission_attachments",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(sent, 1);
    let new_path = new_attachment.path();
    drop(new_attachment);
    store.collect().unwrap();
    assert!(attachment.is_file());
    assert!(new_path.is_file());
}

#[tokio::test]
async fn a_definite_rejection_records_the_outcome_and_preserves_the_draft() {
    let (mut fixture, prepared, _operation, draft, attachment) = Fixture::prepared().await;
    let engine = &fixture.engine;
    let client = &fixture.transport.client;
    let store = &fixture.store;
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.submit_prepared(prepared, client, store, DEADLINE),
            async {
                let outgoing = next_request(&mut fixture.server).await;
                let rejection = encode_frame(&json!({
                    "id": outgoing["id"],
                    "error": {"code": -32000, "message": "fixture rejection"}
                }))
                .unwrap();
                fixture.replies.write_all(&rejection).await.unwrap();
            }
        )
    })
    .await
    .unwrap();
    let reply = reply.unwrap();
    assert!(matches!(reply.response, Err(RequestError::Remote(_))));
    assert_eq!(reply.acknowledgement, SubmissionAcknowledgement::Rejected);
    let db = open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
    let code: i64 = db
        .query_row(
            "SELECT rejection_code FROM submission_outcomes",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(code, -32000);
    let saved = read_draft(&db, draft).unwrap().unwrap();
    assert_eq!(saved.revision, DraftRevision::INITIAL);
    assert_eq!(saved.text, "  café\n");
    store.collect().unwrap();
    assert!(attachment.is_file());
}

#[tokio::test]
async fn stop_blocks_a_journaled_turn_queued_behind_a_full_pipe() {
    verify_blocked_dispatch(Interruption::Stop).await;
}

#[tokio::test]
async fn checkout_replacement_blocks_a_journaled_turn_queued_behind_a_full_pipe() {
    verify_blocked_dispatch(Interruption::ReplaceDirectory).await;
}

#[tokio::test]
async fn connection_retirement_blocks_a_journaled_turn_queued_behind_a_full_pipe() {
    verify_blocked_dispatch(Interruption::RetireConnection).await;
}

#[derive(Clone, Copy)]
enum Interruption {
    Stop,
    RetireConnection,
    ReplaceDirectory,
}

async fn verify_blocked_dispatch(interruption: Interruption) {
    let (mut fixture, prepared, operation, _draft, _attachment) = Fixture::prepared().await;
    let client = &fixture.transport.client;
    let engine = &fixture.engine;
    let store = &fixture.store;
    let (response, hold, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            async {
                while client.shared.state.lock().unwrap().entries.len() != 1
                    || client.outbox.capacity() != MAX_PENDING_REQUESTS
                {
                    tokio::task::yield_now().await;
                }
                engine
                    .submit_prepared(prepared, client, store, DEADLINE)
                    .await
                    .unwrap()
                    .response
            },
            client.request("fixture/hold", json!({"bytes": "x".repeat(4096)}), DEADLINE),
            async {
                while client.outbox.capacity() == MAX_PENDING_REQUESTS
                    || client.shared.state.lock().unwrap().entries.len() != 2
                {
                    tokio::task::yield_now().await;
                }
                match interruption {
                    Interruption::Stop => engine
                        .apply(WorkspaceAction::StopSubmission {
                            operation: operation.clone(),
                        })
                        .await
                        .map(|_| ())
                        .unwrap(),
                    Interruption::RetireConnection => {
                        let expected = operation.connection.clone();
                        let mut replacement = expected.clone();
                        replacement.generation = ConnectionGeneration(2);
                        engine
                            .apply(WorkspaceAction::ReplaceConnection {
                                expected,
                                replacement,
                            })
                            .await
                            .unwrap();
                    }
                    Interruption::ReplaceDirectory => {
                        let checkout = fixture.checkout.canonical_path();
                        std::fs::rename(checkout, fixture.scratch.path().join("previous")).unwrap();
                        std::fs::create_dir(checkout).unwrap();
                    }
                }
                let held = next_request(&mut fixture.server).await;
                assert_eq!(held["method"], "fixture/hold");
                if matches!(interruption, Interruption::ReplaceDirectory) {
                    assert!(fixture.server.next_frame().await.unwrap().is_none());
                } else {
                    respond(&mut fixture.replies, held["id"].clone(), Value::Null).await;
                }
            },
        )
    })
    .await
    .unwrap();
    match interruption {
        Interruption::Stop | Interruption::RetireConnection => {
            hold.unwrap();
            assert!(matches!(
                response,
                Err(RequestError::Stopped(Delivery::Unsent))
            ));
        }
        Interruption::ReplaceDirectory => {
            assert!(matches!(
                hold,
                Err(RequestError::Disconnected(Delivery::PossiblySent))
            ));
            assert!(matches!(
                response,
                Err(RequestError::Disconnected(Delivery::Unsent))
            ));
        }
    }
    let db = open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
    let phase: String = db
        .query_row("SELECT phase FROM submissions", [], |row| row.get(0))
        .unwrap();
    assert_eq!(phase, "unsent");
    if matches!(interruption, Interruption::ReplaceDirectory) {
        return;
    }
    let (next, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            client.request("fixture/next", Value::Null, DEADLINE),
            async {
                let next = next_request(&mut fixture.server).await;
                assert_eq!(next["method"], "fixture/next");
                respond(&mut fixture.replies, next["id"].clone(), Value::Null).await;
            }
        )
    })
    .await
    .unwrap();
    next.unwrap();
}
