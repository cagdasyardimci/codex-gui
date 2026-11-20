use tempfile::{TempDir, tempdir};

use super::*;
use crate::{
    identity::{OperationIdentity, RequestId},
    storage::{
        attachments::AttachmentStore,
        drafts::{DraftId, DraftRevision},
        open_workspace_database,
    },
    workspace::{
        PreparedThread, SendDraft, SendIntent, SendSettings, WorkspaceAction, WorkspaceEngine,
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
}

#[tokio::test]
async fn first_turn_writes_the_exact_journaled_request_from_a_non_git_checkout() {
    let (mut fixture, prepared, operation, draft, attachment) = Fixture::prepared().await;
    let database =
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
    assert_eq!(reply.response.unwrap()["turn"]["id"], "turn-1");
    store.replace_draft_references(draft, &[]).unwrap();
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
