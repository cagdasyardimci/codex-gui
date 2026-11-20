use super::*;
use crate::storage::attachments::QueueSteerPhase;

#[tokio::test]
async fn recovering_queued_steering_requires_exact_delete_and_steer_evidence_without_replay() {
    time::timeout(QUEUE_SCENARIO_DEADLINE, async {
        let (mut f, prepared, _, draft, image) = Fixture::prepared().await;
        drop(prepared);
        let intent = f.queue_intent(draft, 119);
        let first = entry(119, "  café\n");
        let mut second = entry(120, "preserve the original queued input");
        second.client_user_message_id = "external-client-id".into();
        second.input.push(json!({"type":"image","url":"data:image/png;base64,fixture"}));
        let entries = [first.clone(), second.clone()];
        let client = &f.transport.client;
        let store = &f.store;
        let engine = &f.engine;
        let checkout = &f.checkout;
        let target = queue_target();
        let thread = &target.thread;
        engine.observe_execution_event(client.identity(), &active_turn_event("turn/started", "inProgress")).await.unwrap();
        let (added, ()) = tokio::join!(
            engine.enqueue_follow_up(intent, target.clone(), client, store, DEADLINE),
            async {
                let add = next_request(&mut f.server).await;
                assert_eq!(add["method"], "thread/queue/add");
                respond(&mut f.replies, add["id"].clone(), json!({"queuedSubmission":first})).await;
            }
        );
        assert!(matches!(added.unwrap().acknowledgement, SubmissionAcknowledgement::Queued { .. }));

        for (index, item) in entries.iter().enumerate() {
            let (result, ()) = tokio::join!(
                engine.steer_server_queue_entry(client, store, &target, item, DEADLINE),
                async {
                    queue_read(&mut f.server, &mut f.replies, checkout, &entries).await;
                    let delete = next_request(&mut f.server).await;
                    assert_eq!(delete["method"], "thread/queue/delete");
                    assert_eq!(delete["params"], json!({"threadId":thread.0,"queuedSubmissionId":item.id}));
                    let receipts = store.queue_steering_receipts(checkout, thread).unwrap();
                    let captured = receipts.into_iter().find(|receipt| receipt.client_id == item.client_user_message_id).unwrap();
                    assert_eq!(captured.phase, QueueSteerPhase::Deleting);
                    assert_eq!(captured.input, item.input);
                    assert_eq!(captured.target, target);
                    let lost = if index == 0 {
                        delete
                    } else {
                        respond(&mut f.replies, delete["id"].clone(), json!({"deleted":true})).await;
                        let steer = next_request(&mut f.server).await;
                        assert_eq!(steer["method"], "turn/steer");
                        assert_eq!(steer["params"], json!({
                            "threadId":thread.0,
                            "expectedTurnId":target.turn.0,
                            "clientUserMessageId":item.client_user_message_id,
                            "input":item.input
                        }));
                        let receipts = store.queue_steering_receipts(checkout, thread).unwrap();
                        assert_eq!(
                            receipts.iter().find(|entry| entry.id == captured.id).unwrap().phase,
                            QueueSteerPhase::Steering
                        );
                        steer
                    };
                    let uncertain = encode_frame(&json!({
                        "id":lost["id"], "error":{"code":-32603,"message":"fixture lost the reply"}
                    })).unwrap();
                    f.replies.write_all(&uncertain).await.unwrap();
                }
            );
            assert!(matches!(result, Err(QueueError::Request(RequestError::Remote(_)))));
        }
        assert!(matches!(
            engine.steer_server_queue_entry(client, store, &target, &first, DEADLINE).await,
            Err(QueueError::Changed)
        ));
        assert_eq!(store.queue_steering_receipts(checkout, thread).unwrap().len(), 2);
        assert_eq!(store.pending_submissions(checkout).unwrap().len(), 1);
        assert!(time::timeout(Duration::from_millis(50), f.server.next_frame()).await.is_err());

        for consume in [false, true] {
            let (result, ()) = tokio::join!(
                engine.recover_queued_steering(client, store, thread, DEADLINE),
                async {
                    let current = if consume { &[][..] } else { std::slice::from_ref(&first) };
                    queue_read(&mut f.server, &mut f.replies, checkout, current).await;
                    let history = next_request(&mut f.server).await;
                    assert_eq!(history["method"], "thread/turns/list");
                    assert_eq!(history["params"]["itemsView"], "full");
                    assert_eq!(history["params"]["threadId"], thread.0);
                    let mut data = vec![json!({
                        "id":if consume { &target.turn.0 } else {"wrong-turn"},
                        "status":"completed",
                        "items":[{"type":"userMessage","id":"steered","clientId":second.client_user_message_id,"content":[]}]
                    })];
                    if consume {
                        data.push(json!({
                            "id":"naturally-consumed","status":"completed",
                            "items":[{"type":"userMessage","id":"consumed","clientId":first.client_user_message_id,"content":[]}]
                        }));
                    }
                    respond(&mut f.replies, history["id"].clone(), json!({"data":data,"nextCursor":null})).await;
                }
            );
            assert_eq!(result.unwrap().len(), if consume { 2 } else { 0 });
            assert_eq!(store.queue_steering_receipts(checkout, thread).unwrap().len(), if consume { 0 } else { 2 });
        }
        assert!(store.pending_submissions(checkout).unwrap().is_empty());
        store.collect().unwrap();
        assert!(image.is_file());
        let db = open_workspace_database(&f.scratch.path().join("workspace.sqlite3")).unwrap();
        let sent: i64 = db.query_row("SELECT count(*) FROM sent_submission_attachments", [], |row| row.get(0)).unwrap();
        assert_eq!(sent, 1);
        assert!(time::timeout(Duration::from_millis(50), f.server.next_frame()).await.is_err());
    }).await.unwrap();
}
