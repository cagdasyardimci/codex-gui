use tempfile::tempdir;

use super::*;
use crate::{
    identity::{OperationIdentity, RequestId, ThreadId, TurnId},
    storage::drafts::{DraftId, DraftRevision},
    workspace::{
        CommandExecution, ExecutionTarget, InterruptError, SendDraft, SendIntent, SendSettings,
        WorkspaceAction, WorkspaceEngine, WorkspaceError,
    },
};

#[tokio::test]
async fn interruption_leaves_commands_unresolved_until_matching_terminal_evidence() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout));
    let client = &transport.client;
    let owner = client.identity();
    let (engine, _effects) = WorkspaceEngine::start(owner.clone());
    let hidden = ExecutionTarget {
        thread: ThreadId("hidden-thread".into()),
        turn: TurnId("turn-1".into()),
    };
    let later = ExecutionTarget {
        thread: ThreadId("next-thread".into()),
        turn: TurnId("turn-2".into()),
    };
    for (index, execution) in [(1, &hidden), (2, &later)] {
        let operation = operation(owner, index);
        engine
            .apply(WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
                operation: operation.clone(),
                draft: SendDraft {
                    id: DraftId(Uuid::from_u128(index)),
                    revision: DraftRevision::INITIAL,
                    text: "fixture".into(),
                    context: Vec::new(),
                    attachments: Vec::new(),
                },
                settings: SendSettings::default(),
            })))
            .await
            .unwrap();
        engine
            .apply(WorkspaceAction::ThreadPrepared {
                operation,
                thread: execution.thread.clone(),
            })
            .await
            .unwrap();
        engine
            .observe_execution_event(owner, &turn_event("turn/started", execution, "inProgress"))
            .await
            .unwrap();
        engine
            .observe_execution_event(
                owner,
                &command_event("item/started", execution, "inProgress"),
            )
            .await
            .unwrap();
    }

    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let (reply, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.interrupt(operation(owner, 3), hidden.clone(), client, DEADLINE),
            async {
                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "turn/interrupt");
                assert_eq!(
                    request["params"],
                    json!({"threadId":"hidden-thread","turnId":"turn-1"})
                );
                respond(&mut server_out, request["id"].clone(), json!({})).await;
            }
        )
    })
    .await
    .unwrap();
    reply.unwrap();
    assert_eq!(
        engine.snapshot().execution.active_turns,
        [hidden.clone(), later.clone()]
    );
    assert!(matches!(
        engine
            .interrupt(operation(owner, 4), hidden.clone(), client, DEADLINE)
            .await,
        Err(InterruptError::Workspace(WorkspaceError::InterruptPending))
    ));

    engine
        .observe_execution_event(owner, &turn_event("turn/completed", &hidden, "interrupted"))
        .await
        .unwrap();
    assert_eq!(
        engine.snapshot().execution.active_turns,
        std::slice::from_ref(&later)
    );
    assert_eq!(
        engine.snapshot().execution.unresolved_commands,
        [
            CommandExecution {
                target: hidden.clone(),
                item: "command-1".into()
            },
            CommandExecution {
                target: later.clone(),
                item: "command-1".into()
            },
        ]
    );
    assert!(matches!(
        engine
            .interrupt(operation(owner, 5), hidden.clone(), client, DEADLINE)
            .await,
        Err(InterruptError::Workspace(WorkspaceError::InactiveTurn))
    ));
    engine
        .observe_execution_event(owner, &command_event("item/completed", &later, "completed"))
        .await
        .unwrap();
    assert_eq!(
        engine.snapshot().execution.unresolved_commands,
        [CommandExecution {
            target: hidden.clone(),
            item: "command-1".into()
        },]
    );

    let mut replacement = owner.clone();
    replacement.generation = ConnectionGeneration(2);
    engine
        .apply(WorkspaceAction::ReplaceConnection {
            expected: owner.clone(),
            replacement: replacement.clone(),
        })
        .await
        .unwrap();
    let late_exit = command_event("item/completed", &hidden, "failed");
    assert_eq!(
        engine.observe_execution_event(owner, &late_exit).await,
        Err(WorkspaceError::Retired)
    );
    assert_eq!(engine.snapshot().execution.unresolved_commands.len(), 1);
    engine
        .observe_execution_event(&replacement, &late_exit)
        .await
        .unwrap();
    assert!(engine.snapshot().execution.unresolved_commands.is_empty());
}

fn operation(owner: &ConnectionIdentity, index: u128) -> OperationIdentity {
    OperationIdentity {
        connection: owner.clone(),
        request: RequestId(Uuid::from_u128(index)),
    }
}

fn turn_event(method: &str, execution: &ExecutionTarget, status: &str) -> ServerEvent {
    ServerEvent::Notification {
        method: method.into(),
        params: json!({"threadId": execution.thread.0, "turn": {"id": execution.turn.0, "status": status}}),
    }
}

fn command_event(method: &str, execution: &ExecutionTarget, status: &str) -> ServerEvent {
    ServerEvent::Notification {
        method: method.into(),
        params: json!({
            "threadId": execution.thread.0, "turnId": execution.turn.0,
            "item": {"id":"command-1", "type": "commandExecution", "status": status}
        }),
    }
}
