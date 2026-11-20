use super::*;
use crate::{
    codex::{CodexBrowser, QueuedSubmission},
    storage::attachments::queue_edits::QueueEditError,
    workspace::{QueueDeleteResult, QueueEditResult, QueueError, QueueStartResult},
};

const QUEUE_SCENARIO_DEADLINE: Duration = Duration::from_secs(25);

#[path = "queue_legacy.rs"]
mod legacy;

fn entry(index: u128, text: &str) -> QueuedSubmission {
    QueuedSubmission {
        id: format!("queued-{index}"),
        client_user_message_id: Uuid::from_u128(index).to_string(),
        input: vec![json!({"type":"text", "text":text, "text_elements":[]})],
    }
}

#[tokio::test]
async fn only_confirmed_deletion_releases_the_captured_queue_attachment() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut fixture, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let request = fixture.queue_intent(draft, 97);
        let client = &fixture.transport.client;
        let engine = &fixture.engine;
        let store = &fixture.store;
        let checkout = &fixture.checkout;
        let thread = ThreadId("thread-1".into());
        let queued = entry(97, "  café\n");
        let entries = std::slice::from_ref(&queued);
        engine
            .observe_execution_event(
                client.identity(),
                &active_turn_event("turn/started", "inProgress"),
            )
            .await
            .unwrap();
        let (added, ()) = tokio::join!(
            engine.enqueue_follow_up(request, queue_target(), client, store, DEADLINE),
            async {
                let add = next_request(&mut fixture.server).await;
                assert_eq!(add["method"], "thread/queue/add");
                respond(
                    &mut fixture.replies,
                    add["id"].clone(),
                    json!({"queuedSubmission":queued}),
                )
                .await;
            }
        );
        assert_eq!(
            added.unwrap().acknowledgement,
            SubmissionAcknowledgement::Queued {
                retired_draft: true
            }
        );
        store
            .save_editor_text(draft, "independent unsent input".into())
            .unwrap();

        let mut wrong = queued.clone();
        wrong.client_user_message_id = Uuid::from_u128(98).to_string();
        let (replaced, ()) = tokio::join!(
            engine.delete_queue_entry(client, store, &thread, &wrong, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries),
        );
        assert!(matches!(replaced, Err(QueueError::Changed)));
        let (disappeared, ()) = tokio::join!(
            engine.delete_queue_entry(client, store, &thread, &queued, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, &[]),
        );
        assert_eq!(disappeared.unwrap(), QueueDeleteResult::NotConfirmed);
        store.collect().unwrap();
        assert!(image.is_file());
        for deleted in [false, true] {
            let (result, ()) = tokio::join!(
                engine.delete_queue_entry(client, store, &thread, &queued, DEADLINE),
                async {
                    queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries).await;
                    let delete = next_request(&mut fixture.server).await;
                    assert_eq!(delete["method"], "thread/queue/delete");
                    assert_eq!(
                        delete["params"],
                        json!({"threadId":"thread-1","queuedSubmissionId":"queued-97"})
                    );
                    respond(
                        &mut fixture.replies,
                        delete["id"].clone(),
                        json!({"deleted":deleted}),
                    )
                    .await;
                }
            );
            assert_eq!(
                result.unwrap(),
                if deleted {
                    QueueDeleteResult::Deleted
                } else {
                    QueueDeleteResult::NotConfirmed
                }
            );
            store.collect().unwrap();
            assert_eq!(image.is_file(), !deleted);
            assert_eq!(
                store.read_editor_draft(draft).unwrap().text,
                "independent unsent input"
            );
        }
        assert!(store.pending_submissions(checkout).unwrap().is_empty());
        assert!(
            time::timeout(Duration::from_millis(50), fixture.server.next_frame())
                .await
                .is_err()
        );
    })
    .await
    .unwrap();
}

async fn queue_read(
    server: &mut JsonlReader<ReadHalf<DuplexStream>>,
    replies: &mut WriteHalf<DuplexStream>,
    checkout: &CheckoutIdentity,
    entries: &[QueuedSubmission],
) {
    let request = queue_read_request(server, replies, checkout).await;
    respond(replies, request, json!({"data":entries,"nextCursor":null})).await;
}

async fn queue_read_request(
    server: &mut JsonlReader<ReadHalf<DuplexStream>>,
    replies: &mut WriteHalf<DuplexStream>,
    checkout: &CheckoutIdentity,
) -> Value {
    let summary = next_request(server).await;
    assert_eq!(summary["method"], "thread/read");
    assert_eq!(
        summary["params"],
        json!({"threadId":"thread-1","includeTurns":false})
    );
    respond(replies, summary["id"].clone(), json!({
        "thread":{"id":"thread-1","cwd":checkout.canonical_path(),"preview":"","createdAt":0,"updatedAt":0,"status":{"type":"idle"}}
    })).await;
    let list = next_request(server).await;
    assert_eq!(list["method"], "thread/queue/list");
    assert_eq!(list["params"]["threadId"], "thread-1");
    list["id"].clone()
}

#[tokio::test]
async fn starting_a_captured_entry_preserves_its_receipt_through_idle_and_removal_races() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut fixture, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let queued = entry(99, "  café\n");
        let entries = std::slice::from_ref(&queued);
        let request = fixture.queue_intent(draft, 99);
        let client = &fixture.transport.client;
        let engine = &fixture.engine;
        let store = &fixture.store;
        let checkout = &fixture.checkout;
        let thread = ThreadId("thread-1".into());
        engine
            .observe_execution_event(
                client.identity(),
                &active_turn_event("turn/started", "inProgress"),
            )
            .await
            .unwrap();
        let (added, ()) = tokio::join!(
            engine.enqueue_follow_up(request, queue_target(), client, store, DEADLINE),
            async {
                let add = next_request(&mut fixture.server).await;
                assert_eq!(add["method"], "thread/queue/add");
                respond(
                    &mut fixture.replies,
                    add["id"].clone(),
                    json!({"queuedSubmission":queued}),
                )
                .await;
            }
        );
        assert!(matches!(
            added.unwrap().acknowledgement,
            SubmissionAcknowledgement::Queued { .. }
        ));
        assert_eq!(
            engine
                .start_queue_entry(client, store, &thread, &queued, DEADLINE)
                .await
                .unwrap(),
            QueueStartResult::ActiveTurn,
        );
        engine
            .observe_execution_event(
                client.identity(),
                &active_turn_event("turn/completed", "interrupted"),
            )
            .await
            .unwrap();
        store
            .save_editor_text(draft, "independent input".into())
            .unwrap();

        let db =
            open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
        let references = || -> (i64, i64) {
            db.query_row(
                "SELECT (SELECT count(*) FROM submission_attachments),
                        (SELECT count(*) FROM sent_submission_attachments)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap()
        };
        let (gone, ()) = tokio::join!(
            engine.start_queue_entry(client, store, &thread, &queued, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, &[]),
        );
        assert_eq!(gone.unwrap(), QueueStartResult::Missing);
        assert_eq!(references(), (1, 0));

        for (error, expected) in [
            (
                Some("thread already has an active or pending turn"),
                QueueStartResult::ActiveTurn,
            ),
            (
                Some("queued submission not found: queued-99"),
                QueueStartResult::Missing,
            ),
            (
                None,
                QueueStartResult::Started(TurnId("queued-turn".into())),
            ),
        ] {
            let (started, ()) = tokio::join!(
                engine.start_queue_entry(client, store, &thread, &queued, DEADLINE),
                async {
                    queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries).await;
                    let start = next_request(&mut fixture.server).await;
                    assert_eq!(start["method"], "thread/queue/start");
                    assert_eq!(
                        start["params"],
                        json!({"threadId":"thread-1", "queuedSubmissionId":"queued-99"})
                    );
                    if let Some(message) = error {
                        let reject = encode_frame(&json!({
                            "id":start["id"],"error":{"code":-32600,"message":message}
                        }))
                        .unwrap();
                        fixture.replies.write_all(&reject).await.unwrap();
                    } else {
                        respond(
                            &mut fixture.replies,
                            start["id"].clone(),
                            json!({
                                "turn":{"id":"queued-turn","status":"inProgress"}
                            }),
                        )
                        .await;
                    }
                }
            );
            assert_eq!(started.unwrap(), expected);
            assert_eq!(references(), if error.is_some() { (1, 0) } else { (0, 1) });
            assert_eq!(
                store.read_editor_draft(draft).unwrap().text,
                "independent input"
            );
            store.collect().unwrap();
            assert!(image.is_file());
        }
        assert!(engine.snapshot().execution.active_turns.is_empty());
        assert!(
            time::timeout(Duration::from_millis(50), fixture.server.next_frame())
                .await
                .is_err()
        );
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn editing_keeps_other_drafts_and_preserves_input_if_codex_consumes_the_entry() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut fixture, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let db = open_workspace_database(&fixture.scratch.path().join("workspace.sqlite3")).unwrap();
        let request = fixture.queue_intent(draft, 94);
        let client = &fixture.transport.client;
        let engine = &fixture.engine;
        let store = &fixture.store;
        let checkout = &fixture.checkout;
        let thread = ThreadId("thread-1".into());
        let other_draft = store.editable_thread_draft(&ThreadId("other".into())).unwrap();
        store.save_editor_text(other_draft, "independent chat".into()).unwrap();
        let attachment = json!({"type":"image", "url":"data:image/png;base64,fixture"});
        let mut queued = entry(94, "  café\n");
        queued.input.push(attachment.clone());
        let entries = std::slice::from_ref(&queued);
        engine.observe_execution_event(client.identity(), &active_turn_event("turn/started", "inProgress")).await.unwrap();
        let (added, ()) = tokio::join!(
            engine.enqueue_follow_up(request, queue_target(), client, store, DEADLINE),
            async {
                let add = next_request(&mut fixture.server).await;
                assert_eq!(add["method"], "thread/queue/add");
                respond(&mut fixture.replies, add["id"].clone(), json!({"queuedSubmission":queued})).await;
            }
        );
        assert_eq!(added.unwrap().acknowledgement, SubmissionAcknowledgement::Queued { retired_draft: true });

        store.save_editor_text(draft, "occupied draft".into()).unwrap();
        let (blocked, ()) = tokio::join!(
            engine.begin_queue_edit(client, store, &thread, &queued, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries),
        );
        assert!(matches!(blocked, Err(QueueError::Edit(QueueEditError::OccupiedDraft))));
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "occupied draft");
        store.save_editor_text(draft, String::new()).unwrap();

        let (original, ()) = tokio::join!(
            engine.begin_queue_edit(client, store, &thread, &queued, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries),
        );
        let original = original.unwrap();
        store.save_editor_text(draft, "cancel this edit".into()).unwrap();
        let (cancelled, ()) = tokio::join!(
            engine.cancel_queue_edit(client, store, &original, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries),
        );
        cancelled.unwrap();
        assert_eq!(store.read_editor_draft(draft).unwrap().text, "");
        assert!(store.queue_edit(checkout, &thread).unwrap().is_none());
        store.collect().unwrap();
        assert!(image.is_file());

        let (edit, ()) = tokio::join!(
            engine.begin_queue_edit(client, store, &thread, &queued, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries),
        );
        let edit = edit.unwrap();
        assert_ne!(edit.id, original.id);
        store.save_editor_text(draft, "updated queue entry".into()).unwrap();
        let mut updated = entry(94, "updated queue entry");
        updated.input.push(attachment.clone());
        let (saved, ()) = tokio::join!(
            engine.save_queue_edit(client, store, &edit, DEADLINE),
            async {
                queue_read(&mut fixture.server, &mut fixture.replies, checkout, entries).await;
                let update = next_request(&mut fixture.server).await;
                assert_eq!(update["method"], "thread/queue/update");
                assert_eq!(update["params"], json!({
                    "threadId":"thread-1","queuedSubmissionId":"queued-94","input":updated.input
                }));
                store.save_editor_text(draft, "newer text while updating".into()).unwrap();
                respond(&mut fixture.replies, update["id"].clone(), json!({"queuedSubmission":updated})).await;
            }
        );
        assert_eq!(saved.unwrap(), QueueEditResult::Updated);
        let saved_edit = store.queue_edit(checkout, &thread).unwrap().unwrap();
        assert_eq!(saved_edit.entry, updated);
        let rendered = engine.route_session_event(client, store, ServerEvent::Notification {
            method: "item/started".into(),
            params: json!({
                "threadId":"thread-1", "turnId":"next-turn",
                "item":{"type":"userMessage", "id":"consumed", "clientId":updated.client_user_message_id}
            }),
        }, DEADLINE).await.unwrap();
        assert!(rendered.is_some());
        assert!(store.queue_edit(checkout, &thread).unwrap().is_none());
        let saved_draft = store.read_editor_draft(draft).unwrap();
        assert_eq!(saved_draft.text, "newer text while updating");
        assert_eq!(saved_draft.context, [attachment]);
        assert_eq!(store.read_editor_draft(other_draft).unwrap().text, "independent chat");
        let refs: (i64, i64, i64) = db.query_row(
            "SELECT (SELECT count(*) FROM draft_attachments),
                    (SELECT count(*) FROM submission_attachments),
                    (SELECT count(*) FROM sent_submission_attachments)",
            [], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?)),
        ).unwrap();
        assert_eq!(refs, (1, 0, 1));
        assert!(time::timeout(Duration::from_millis(50), fixture.server.next_frame()).await.is_err());
    }).await.unwrap();
}

#[tokio::test]
async fn reordering_reconciles_a_concurrent_member_and_an_uncertain_reply_without_history_reads() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut fixture, _prepared, _, _, _) = Fixture::prepared().await;
        let client = &fixture.transport.client;
        let engine = &fixture.engine;
        let checkout = &fixture.checkout;
        let browser = CodexBrowser::new(client.clone());
        let thread = ThreadId("thread-1".into());
        let initial = vec![entry(1, "first"), entry(2, "second")];
        let mut current = initial.clone();
        current.push(entry(3, "concurrent add"));
        let (captured, ()) = tokio::join!(
            async {
                let summary = browser.thread_summary(&thread, DEADLINE).await.unwrap();
                browser.queue_snapshot(&summary, DEADLINE).await.unwrap()
            },
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, &initial),
        );
        let desired = [initial[1].id.clone(), initial[0].id.clone()];
        let (stale, ()) = tokio::join!(
            engine.reorder_queue(client, &thread, &captured, &desired, DEADLINE),
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, &current),
        );
        assert!(matches!(stale, Err(QueueError::Changed)));
        let (captured, ()) = tokio::join!(
            async {
                let summary = browser.thread_summary(&thread, DEADLINE).await.unwrap();
                browser.queue_snapshot(&summary, DEADLINE).await.unwrap()
            },
            queue_read(&mut fixture.server, &mut fixture.replies, checkout, &current),
        );
        let mut reordered = current.clone();
        reordered.rotate_right(1);
        let ordered_ids: Vec<_> = reordered.iter().map(|entry| entry.id.clone()).collect();
        let (outcome, ()) = tokio::join!(
            engine.reorder_queue(client, &thread, &captured, &ordered_ids, DEADLINE),
            async {
                queue_read(&mut fixture.server, &mut fixture.replies, checkout, &current).await;
                let reorder = next_request(&mut fixture.server).await;
                assert_eq!(reorder["method"], "thread/queue/reorder");
                assert_eq!(reorder["params"], json!({"threadId":"thread-1","queuedSubmissionIds":ordered_ids}));
                let failed = encode_frame(&json!({
                    "id":reorder["id"],"error":{"code":-32603,"message":"fixture failed after commit"}
                })).unwrap();
                fixture.replies.write_all(&failed).await.unwrap();
                queue_read(&mut fixture.server, &mut fixture.replies, checkout, &reordered).await;
            }
        );
        assert_eq!(outcome.unwrap(), reordered);
        assert!(time::timeout(Duration::from_millis(50), fixture.server.next_frame()).await.is_err());
    }).await.unwrap();
}
