use std::path::Path;

use tempfile::tempdir;

use super::*;
use crate::{
    codex::QueueSnapshot,
    identity::ThreadId,
    storage::attachments::AttachmentStore,
    workspace::{ResumedMode, RoutedEvent, WorkspaceEngine},
};

#[tokio::test]
async fn cold_resume_routes_early_work_and_reconciles_remote_commands_without_replay() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let store = AttachmentStore::open(&scratch.path().join("workspace.sqlite3")).unwrap();
    let (mut transport, input, mut replies) = transport_for(4096, 2, Some(checkout.clone()));
    let client = &transport.client;
    let incoming = &mut transport.inbox;
    let owner = client.identity();
    let (engine, _effects) = WorkspaceEngine::start(owner.clone());
    let thread = ThreadId("hidden".into());
    let mut server = JsonlReader::new(input, MAX_FRAME_BYTES);
    let (result, ()) = time::timeout(DEADLINE, async {
        tokio::join!(engine.resume_with_events(client, incoming, &store, &thread, DEADLINE), async {
            expect_summary(&mut server, &mut replies, checkout.canonical_path()).await;
            let request = next_request(&mut server).await;
            assert_eq!(request["method"], "thread/resume");
            assert_eq!(request["params"], json!({"threadId":"hidden","excludeTurns":true}));
            for event in [
                json!({"method":"turn/started","params":{"threadId":"hidden","turn":{"id":"cold","status":"inProgress"}}}),
                json!({"method":"thread/queue/changed","params":{"threadId":"hidden"}}),
                json!({"id":22,"method":"item/commandExecution/requestApproval",
                       "params":{"threadId":"hidden","turnId":"cold","itemId":"command","availableDecisions":["decline"]}}),
                json!({"id":"gate","method":"fixture/event-barrier","params":{}}),
            ] {
                write_event(&mut replies, event).await;
            }
            let gate = next_request(&mut server).await;
            assert_eq!(gate["id"], "gate");
            assert_eq!(gate["error"]["code"], -32601);
            assert!(engine.snapshot().writable_threads.is_empty());
            respond(&mut replies, request["id"].clone(), json!({
                "thread":chat(checkout.canonical_path()), "cwd":checkout.canonical_path()
            })).await;
            let queue = next_request(&mut server).await;
            assert_eq!(queue["method"], "thread/queue/list");
            assert!(engine.snapshot().writable_threads.contains(&thread));
            assert_eq!(engine.snapshot().execution.active_turns[0].turn.0, "cold");
            respond(&mut replies, queue["id"].clone(), json!({"data":[],"nextCursor":null})).await;

            let statuses = next_request(&mut server).await;
            assert_eq!(statuses["method"], "thread/turns/list");
            assert_eq!(statuses["params"]["itemsView"], "notLoaded");
            respond(&mut replies, statuses["id"].clone(), json!({
                "data":[{"id":"cold","status":"inProgress","items":[]}],"nextCursor":null
            })).await;
            let history = next_request(&mut server).await;
            assert_eq!(history["method"], "thread/turns/list");
            assert_eq!(history["params"]["itemsView"], "full");
            respond(&mut replies, history["id"].clone(), json!({
                "data":[{"id":"cold","status":"inProgress","items":[
                    {"type":"commandExecution","id":"remote-command","status":"inProgress"}
                ]}],"nextCursor":null
            })).await;
        })
    }).await.unwrap();
    let resumed = result.unwrap();
    let ResumedMode::Writable { queue, execution } = resumed.mode else {
        panic!("expected verified writer")
    };
    execution.unwrap();
    assert!(
        matches!(queue.unwrap().for_selection(owner, &thread).unwrap(), QueueSnapshot::Available(queue) if queue.is_empty())
    );
    assert!(matches!(&resumed.events[..], [
        RoutedEvent::QueueChanged(changed), RoutedEvent::Interaction(approval)
    ] if changed == &thread && approval.identity.thread == thread && approval.identity.request == RpcId::Integer(22)));
    let snapshot = engine.snapshot();
    assert_eq!(
        snapshot.execution.unresolved_commands[0].item,
        "remote-command"
    );
    assert_eq!(
        snapshot.execution.unresolved_commands[0].target.thread,
        thread
    );
    assert_eq!(
        snapshot.execution.unresolved_commands[0].target.turn.0,
        "cold"
    );
}

#[tokio::test]
async fn competing_writer_keeps_history_readable_and_never_routes_foreign_approvals() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let store = AttachmentStore::open(&scratch.path().join("workspace.sqlite3")).unwrap();
    let (mut transport, input, mut replies) = transport_for(4096, 2, Some(checkout.clone()));
    let client = &transport.client;
    let (engine, _effects) = WorkspaceEngine::start(client.identity().clone());
    let thread = ThreadId("hidden".into());
    let mut server = JsonlReader::new(input, MAX_FRAME_BYTES);
    let (result, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.resume_with_events(client, &mut transport.inbox, &store, &thread, DEADLINE),
            async {
                expect_summary(&mut server, &mut replies, checkout.canonical_path()).await;
                let resume = next_request(&mut server).await;
                assert_eq!(resume["method"], "thread/resume");
                write_event(
                    &mut replies,
                    json!({"id":23,"method":"item/commandExecution/requestApproval",
                "params":{"threadId":"hidden","turnId":"foreign","itemId":"foreign-command"}}),
                )
                .await;
                write_event(
                    &mut replies,
                    json!({"id":resume["id"],"error":{
                        "code":-32000,"message":"thread already has an active writer"
                    }}),
                )
                .await;
            }
        )
    })
    .await
    .unwrap();
    let resumed = result.unwrap();
    assert!(matches!(resumed.mode, ResumedMode::ReadOnly));
    assert!(resumed.events.is_empty());
    assert!(engine.snapshot().writable_threads.is_empty());
    assert!(engine.snapshot().execution.active_turns.is_empty());
    let browser = crate::codex::CodexBrowser::new(client.clone());
    let (history, ()) = time::timeout(DEADLINE, async {
        tokio::join!(browser.history(&resumed.summary, None, DEADLINE), async {
            let read = next_request(&mut server).await;
            assert_eq!(read["method"], "thread/turns/list");
            assert_eq!(read["params"]["threadId"], "hidden");
            respond(
                &mut replies,
                read["id"].clone(),
                json!({
                    "data":[{"id":"foreign","status":"inProgress","items":[]}],"nextCursor":null
                }),
            )
            .await;
        })
    })
    .await
    .unwrap();
    assert_eq!(
        history
            .unwrap()
            .for_selection(client.identity(), &thread)
            .unwrap()
            .data[0]
            .activity
            .id
            .0,
        "foreign"
    );
    assert!(engine.snapshot().execution.active_turns.is_empty());
}

async fn expect_summary(
    server: &mut JsonlReader<ReadHalf<DuplexStream>>,
    replies: &mut WriteHalf<DuplexStream>,
    cwd: &Path,
) {
    let request = next_request(server).await;
    assert_eq!(request["method"], "thread/read");
    assert_eq!(
        request["params"],
        json!({"threadId":"hidden","includeTurns":false})
    );
    respond(replies, request["id"].clone(), json!({"thread":chat(cwd)})).await;
}

fn chat(cwd: &Path) -> Value {
    json!({"id":"hidden","cwd":cwd,"preview":"","createdAt":0,"updatedAt":0,"status":{"type":"idle"}})
}

async fn write_event(replies: &mut WriteHalf<DuplexStream>, value: Value) {
    replies
        .write_all(&encode_frame(&value).unwrap())
        .await
        .unwrap();
}
