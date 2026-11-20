use super::*;
use crate::{
    codex::{ChatRead, QueueSnapshot},
    storage::attachments::{LegacyQueueStatus, QueueSteerPhase, appkit_drafts::AppKitDraftCopy},
    workspace::LegacyStartResult,
};

async fn availability(
    client: &AppServerClient,
    server: &mut JsonlReader<ReadHalf<DuplexStream>>,
    replies: &mut WriteHalf<DuplexStream>,
    checkout: &CheckoutIdentity,
    available: bool,
) -> ChatRead<QueueSnapshot> {
    let thread = ThreadId("thread-1".into());
    let browser = CodexBrowser::new(client.clone());
    let (snapshot, ()) = tokio::join!(
        async {
            let chat = browser.thread_summary(&thread, DEADLINE).await.unwrap();
            browser.queue_snapshot(&chat, DEADLINE).await.unwrap()
        },
        async {
            let id = queue_read_request(server, replies, checkout).await;
            if available {
                respond(replies, id, json!({"data":[],"nextCursor":null})).await;
            } else {
                let unavailable = encode_frame(&json!({
                    "id":id,"error":{"code":-32600,"message":"user message queue is unavailable"}
                }))
                .unwrap();
                replies.write_all(&unavailable).await.unwrap();
            }
        }
    );
    snapshot
}

fn states(
    store: &AttachmentStore,
    client: &AppServerClient,
    thread: &ThreadId,
) -> Vec<(RequestId, LegacyQueueStatus)> {
    let owner = client.identity();
    store
        .legacy_queue(owner.workspace.checkout.as_ref().unwrap(), thread, owner)
        .unwrap()
        .into_iter()
        .map(|entry| (entry.id, entry.status))
        .collect()
}

#[tokio::test]
async fn a_saved_appkit_entry_requires_explicit_resume_even_with_a_server_queue() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut f, prepared, _, draft, _) = Fixture::prepared().await;
        drop(prepared);
        let client = &f.transport.client;
        let store = &f.store;
        let checkout = &f.checkout;
        let engine = &f.engine;
        let thread = ThreadId("thread-1".into());
        let id = RequestId(Uuid::new_v4());
        let appkit_id = id.0.to_string().to_ascii_uppercase();
        let payload = serde_json::to_vec(&json!([
            {
                "id":appkit_id,"text":"Saved AppKit follow-up","context":[],
                "modelID":"copied-model","effort":"high","serviceTier":"fast"
            }
        ]))
        .unwrap();
        let mut chats = plist::Dictionary::new();
        chats.insert("thread:thread-1".into(), plist::Value::Data(payload));
        let mut projects = plist::Dictionary::new();
        projects.insert(
            checkout.canonical_path().to_str().unwrap().into(),
            plist::Value::Dictionary(chats),
        );
        let mut preferences = plist::Dictionary::new();
        preferences.insert(
            "CodexGUI.queuedMessages".into(),
            plist::Value::Dictionary(projects),
        );
        let source = f.scratch.path().join("copied-preferences.plist");
        plist::to_file_xml(&source, &preferences).unwrap();
        store
            .import_appkit_queues(
                AppKitDraftCopy {
                    preferences: &source,
                    original_images: f.scratch.path(),
                    copied_images: f.scratch.path(),
                },
                checkout,
            )
            .unwrap();
        let evidence = availability(client, &mut f.server, &mut f.replies, checkout, true).await;
        assert!(matches!(
            engine
                .start_legacy_queue(client, store, &thread, &evidence, None, DEADLINE)
                .await,
            Err(QueueError::ServerQueueAvailable)
        ));
        assert_eq!(
            states(store, client, &thread),
            [(id, LegacyQueueStatus::Paused)]
        );
        let server_entries = [entry(17, "Server-owned entry")];
        let (waiting, ()) = tokio::join!(
            engine.start_legacy_queue(client, store, &thread, &evidence, Some(id), DEADLINE),
            queue_read(&mut f.server, &mut f.replies, checkout, &server_entries),
        );
        assert_eq!(waiting.unwrap(), LegacyStartResult::NotReady);
        let (resumed, ()) = tokio::join!(
            engine.start_legacy_queue(client, store, &thread, &evidence, Some(id), DEADLINE),
            async {
                queue_read(&mut f.server, &mut f.replies, checkout, &[]).await;
                let start = next_request(&mut f.server).await;
                assert_eq!(start["method"], "turn/start");
                assert_eq!(start["params"]["threadId"], thread.0);
                assert_eq!(start["params"]["clientUserMessageId"], appkit_id);
                assert_eq!(
                    start["params"]["input"],
                    json!([{"type":"text","text":"Saved AppKit follow-up"}])
                );
                assert_eq!(start["params"]["model"], "copied-model");
                assert_eq!(start["params"]["effort"], "high");
                assert_eq!(start["params"]["serviceTierForTurn"], "fast");
                respond(
                    &mut f.replies,
                    start["id"].clone(),
                    json!({"turn":{"id":"explicit-resume"}}),
                )
                .await;
            }
        );
        assert_eq!(
            resumed.unwrap(),
            LegacyStartResult::Started(TurnId("explicit-resume".into()))
        );
        assert!(states(store, client, &thread).is_empty());
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "  café\n");
        assert!(
            time::timeout(Duration::from_millis(50), f.server.next_frame())
                .await
                .is_err()
        );
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn a_rejected_legacy_steer_restores_its_attachment_only_into_an_empty_draft() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut f, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let intent = f.queue_intent(draft, 111);
        let client = &f.transport.client;
        let target = queue_target();
        let thread = &target.thread;
        let engine = &f.engine;
        let store = &f.store;
        let checkout = &f.checkout;
        let support = availability(client, &mut f.server, &mut f.replies, checkout, false).await;
        engine.observe_execution_event(client.identity(), &active_turn_event("turn/started", "inProgress")).await.unwrap();
        let id = engine.enqueue_legacy_follow_up(client, store, target.clone(), &support, intent).await.unwrap();
        let (rejected, ()) = tokio::join!(
            engine.steer_legacy_queue_entry(client, store, &target, &support, id, DEADLINE),
            async {
                let steer = next_request(&mut f.server).await;
                assert_eq!(steer["method"], "turn/steer");
                assert_eq!(steer["params"], json!({
                    "threadId":thread.0,
                    "expectedTurnId":target.turn.0,
                    "clientUserMessageId":id.0.to_string(),
                    "input":[{"type":"text","text":"  café\n"},{"type":"localImage","path":image}],
                }));
                let fail = encode_frame(&json!({
                    "id":steer["id"],"error":{"code":-32600,"message":"the captured turn is unavailable"}
                })).unwrap();
                f.replies.write_all(&fail).await.unwrap();
            }
        );
        assert!(matches!(rejected, Err(QueueError::Request(RequestError::Remote(_)))));
        let receipt = store.queue_steering_receipts(checkout, thread).unwrap().pop().unwrap();
        assert_eq!(receipt.phase, QueueSteerPhase::Detached);
        store.save_editor_text(draft, "another unsent draft".into()).unwrap();
        assert!(matches!(
            engine.restore_detached_steering(client, store, thread, receipt.id).await,
            Err(QueueError::Journal(JournalError::PendingDraft))
        ));
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "another unsent draft");
        store.save_editor_text(draft, String::new()).unwrap();
        assert_eq!(engine.restore_detached_steering(client, store, thread, receipt.id).await.unwrap(), draft);
        let saved = store.read_editor_draft(draft).unwrap();
        assert_eq!(saved.text, "  café\n");
        assert_eq!(saved.context, [json!({"type":"localImage","path":image})]);
        assert!(store.queue_steering_receipts(checkout, thread).unwrap().is_empty());
        assert!(states(store, client, thread).is_empty());
        assert!(store.pending_submissions(checkout).unwrap().is_empty());
        store.collect().unwrap();
        assert!(image.is_file());
        assert!(time::timeout(Duration::from_millis(50), f.server.next_frame()).await.is_err());
    }).await.unwrap();
}

#[tokio::test]
async fn legacy_queue_reopens_paused_and_resumes_captured_settings_in_fifo_order() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut f, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let client = &f.transport.client;
        let store = &f.store;
        let engine = &f.engine;
        let target = queue_target();
        let thread = target.thread.clone();
        let available = availability(client, &mut f.server, &mut f.replies, &f.checkout, true).await;
        let unsupported = availability(client, &mut f.server, &mut f.replies, &f.checkout, false).await;
        let mut first = f.queue_intent(draft, 101);
        let initial = Arc::get_mut(&mut first).unwrap();
        initial.settings.reasoning_effort = Some("high".into());
        initial.settings.service_tier = Some("fast".into());
        assert!(matches!(
            engine.enqueue_legacy_follow_up(client, store, target.clone(), &available, first.clone()).await,
            Err(QueueError::ServerQueueAvailable)
        ));
        engine.observe_execution_event(client.identity(), &active_turn_event("turn/started", "inProgress")).await.unwrap();
        let first = engine.enqueue_legacy_follow_up(client, store, target.clone(), &unsupported, first).await.unwrap();
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "");
        store.save_editor_text(draft, "second queued input".into()).unwrap();
        let second_draft = store.read_editor_draft(draft).unwrap();
        let second = Arc::new(SendIntent {
            operation: OperationIdentity { connection: client.identity().clone(), request: RequestId(Uuid::from_u128(102)) },
            draft: SendDraft {
                id: draft, revision: second_draft.revision, text:second_draft.text,
                context:second_draft.context, attachments:Vec::new(),
            },
            settings: SendSettings { model: Some("second-model".into()), ..SendSettings::default() },
        });
        let second = engine.enqueue_legacy_follow_up(client, store, target, &unsupported, second).await.unwrap();
        assert_eq!(
            states(store, client, &thread),
            [(first, LegacyQueueStatus::Ready), (second, LegacyQueueStatus::Ready)]
        );
        store.save_editor_text(draft, "keep editing the ordinary draft".into()).unwrap();
        engine.route_session_event(client, store, active_turn_event("turn/completed", "interrupted"), DEADLINE).await.unwrap();
        assert_eq!(states(store, client, &thread), [(first, LegacyQueueStatus::Paused), (second, LegacyQueueStatus::Paused)]);
        assert_eq!(engine.start_legacy_queue(client, store, &thread, &unsupported, None, DEADLINE).await.unwrap(), LegacyStartResult::NotReady);
        assert!(time::timeout(Duration::from_millis(50), f.server.next_frame()).await.is_err());

        let Fixture { checkout, scratch, store, .. } = f;
        drop(store);
        let path = scratch.path().join("workspace.sqlite3");
        let store = AttachmentStore::open(&path).unwrap();
        let (transport, server_in, mut replies) = transport_for(4096, 2, Some(checkout.clone()));
        let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
        let client = &transport.client;
        let owner = client.identity();
        let (engine, _) = WorkspaceEngine::start(owner.clone());
        let (stopped, _) = tokio::sync::watch::channel(false);
        engine.apply(WorkspaceAction::ReserveResume { owner: owner.clone(), thread: thread.clone(), stopped }).await.unwrap();
        engine.apply(WorkspaceAction::FinishResume { owner: owner.clone(), thread: thread.clone(), writable: true }).await.unwrap();
        assert!(matches!(
            engine.start_legacy_queue(client, &store, &thread, &unsupported, Some(first), DEADLINE).await,
            Err(QueueError::Browse(crate::codex::BrowseError::StaleChatRead))
        ));
        let unsupported = availability(client, &mut server, &mut replies, &checkout, false).await;
        assert_eq!(states(&store, client, &thread), [(first, LegacyQueueStatus::Paused), (second, LegacyQueueStatus::Paused)]);
        for resume in [None, Some(second)] {
            assert_eq!(engine.start_legacy_queue(client, &store, &thread, &unsupported, resume, DEADLINE).await.unwrap(), LegacyStartResult::NotReady);
        }
        let (started, ()) = tokio::join!(
            engine.start_legacy_queue(client, &store, &thread, &unsupported, Some(first), DEADLINE),
            async {
                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "turn/start");
                assert_eq!(request["params"]["threadId"], thread.0);
                assert_eq!(request["params"]["clientUserMessageId"], first.0.to_string());
                assert_eq!(request["params"]["input"], json!([
                    {"type":"text","text":"  café\n"},{"type":"localImage","path":image}
                ]));
                assert_eq!(request["params"]["model"], "captured-model");
                assert_eq!(request["params"]["effort"], "high");
                assert_eq!(request["params"]["serviceTierForTurn"], "fast");
                respond(&mut replies, request["id"].clone(), json!({"turn":{"id":"resumed"}})).await;
            }
        );
        assert_eq!(started.unwrap(), LegacyStartResult::Started(TurnId("resumed".into())));
        assert_eq!(states(&store, client, &thread), [(second, LegacyQueueStatus::Ready)]);
        let mut next_generation = owner.clone();
        next_generation.generation.0 += 1;
        assert_eq!(store.legacy_queue(&checkout, &thread, &next_generation).unwrap()[0].status, LegacyQueueStatus::Paused);
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "keep editing the ordinary draft");
        store.collect().unwrap();
        assert!(image.is_file());

        engine.route_session_event(client, &store, ServerEvent::Notification {
            method: "turn/completed".into(),
            params: json!({"threadId":thread.0,"turn":{"id":"resumed","status":"failed"}}),
        }, DEADLINE).await.unwrap();
        assert_eq!(states(&store, client, &thread), [(second, LegacyQueueStatus::Paused)]);
        let (lost, ()) = tokio::join!(
            engine.start_legacy_queue(client, &store, &thread, &unsupported, Some(second), DEADLINE),
            async {
                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "turn/start");
                assert_eq!(request["params"]["model"], "second-model");
                assert_eq!(request["params"]["clientUserMessageId"], second.0.to_string());
                let uncertain = encode_frame(&json!({
                    "id":request["id"],"error":{"code":-32603,"message":"fixture lost the accepted reply"}
                })).unwrap();
                replies.write_all(&uncertain).await.unwrap();
            }
        );
        assert!(matches!(lost, Err(QueueError::Request(RequestError::Remote(_)))));
        assert_eq!(states(&store, client, &thread), [(second, LegacyQueueStatus::AwaitingEvidence)]);
        assert_eq!(
            engine.start_legacy_queue(client, &store, &thread, &unsupported, Some(second), DEADLINE).await.unwrap(),
            LegacyStartResult::NotReady
        );
        assert!(time::timeout(Duration::from_millis(50), server.next_frame()).await.is_err());
    }).await.unwrap();
}
