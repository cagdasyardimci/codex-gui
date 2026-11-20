use std::{fs, path::Path};

use serde_json::json;
use tokio::sync::watch;

use crate::{
    codex::ServerEvent,
    identity::TurnId,
    workspace::{CommandExecution, ExecutionTarget, WorkspaceAction},
};

use super::*;

fn checkout(root: &Path, name: &str) -> CheckoutIdentity {
    let path = root.join(name);
    fs::create_dir(&path).unwrap();
    CheckoutIdentity::capture(&path).unwrap()
}

fn owner(checkout: CheckoutIdentity, generation: u64) -> ConnectionIdentity {
    ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::new_v4()),
            checkout: Some(checkout),
        },
        generation: ConnectionGeneration(generation),
    }
}

async fn event(
    engine: &WorkspaceEngine,
    identity: &ConnectionIdentity,
    method: &str,
    params: serde_json::Value,
) {
    engine
        .observe_execution_event(
            identity,
            &ServerEvent::Notification {
                method: method.into(),
                params,
            },
        )
        .await
        .unwrap();
}

#[tokio::test]
async fn cleanup_reserves_one_checkout_and_waits_for_hidden_commands_and_accepted_writes() {
    let root = tempfile::tempdir().unwrap();
    let hidden = checkout(root.path(), "hidden");
    let selected = checkout(root.path(), "selected");
    let store = AttachmentStore::open(&root.path().join("workspace.sqlite3")).unwrap();
    let owners = RuntimeOwners::new(store);
    let hidden_owner = owner(hidden.clone(), 1);
    let selected_owner = owner(selected.clone(), 1);
    let (engine, _effects) = WorkspaceEngine::start(hidden_owner.clone());
    let (displayed, _selected_effects) = WorkspaceEngine::start(selected_owner.clone());
    owners.register(engine.clone()).unwrap();
    owners.register(displayed).unwrap();
    let thread = ThreadId("hidden-thread".into());
    let (stopped, _) = watch::channel(false);
    engine
        .apply(WorkspaceAction::ReserveResume {
            owner: hidden_owner.clone(),
            thread: thread.clone(),
            stopped,
        })
        .await
        .unwrap();
    engine
        .apply(WorkspaceAction::FinishResume {
            owner: hidden_owner.clone(),
            thread: thread.clone(),
            writable: true,
        })
        .await
        .unwrap();
    let queued_write = owners.acquire(&hidden_owner).unwrap();
    event(
        &engine,
        &hidden_owner,
        "turn/started",
        json!({"threadId": thread.0, "turn": {"id": "turn"}}),
    )
    .await;
    event(
        &engine,
        &hidden_owner,
        "item/started",
        json!({
            "threadId": thread.0, "turnId": "turn",
            "item": {"type": "commandExecution", "id": "command", "status": "inProgress"}
        }),
    )
    .await;
    event(
        &engine,
        &hidden_owner,
        "turn/completed",
        json!({
            "threadId": thread.0, "turn": {"id": "turn", "status": "interrupted"}
        }),
    )
    .await;
    let selected_cleanup = owners.reserve_cleanup(&selected).unwrap();
    assert_eq!(selected_cleanup.checkout(), &selected);
    assert!(matches!(
        owners.acquire(&selected_owner),
        Err(OwnerError::Busy)
    ));
    drop(queued_write);
    assert!(matches!(
        owners.reserve_cleanup(&hidden),
        Err(OwnerError::Busy)
    ));

    let disk_write = owners.acquire_write(&hidden).unwrap();
    event(
        &engine,
        &hidden_owner,
        "item/completed",
        json!({
            "threadId": thread.0, "turnId": "turn",
            "item": {"type": "commandExecution", "id": "command", "status": "completed"}
        }),
    )
    .await;
    assert!(matches!(
        owners.reserve_cleanup(&hidden),
        Err(OwnerError::Busy)
    ));
    drop(disk_write);
    let reservation = owners.reserve_cleanup(&hidden).unwrap();
    assert!(matches!(
        owners.acquire_write(&hidden),
        Err(OwnerError::Busy)
    ));
    drop(reservation);
    assert!(owners.acquire(&hidden_owner).is_ok());
}

#[tokio::test]
async fn reopens_unselected_evidence_and_rejects_late_results_from_the_retired_reader() {
    let root = tempfile::tempdir().unwrap();
    let hidden = checkout(root.path(), "hidden");
    let selected = checkout(root.path(), "selected");
    let database = root.path().join("workspace.sqlite3");
    let thread = ThreadId("hidden-thread".into());
    let target = ExecutionTarget {
        thread: thread.clone(),
        turn: TurnId("turn".into()),
    };
    {
        let store = AttachmentStore::open(&database).unwrap();
        store
            .preserve_exit_executions(
                &hidden,
                &ExecutionSnapshot {
                    active_turns: vec![target.clone()],
                    unresolved_commands: vec![CommandExecution {
                        target,
                        item: "command".into(),
                    }],
                },
            )
            .unwrap();
    }
    let store = AttachmentStore::open(&database).unwrap();
    let owners = RuntimeOwners::new(store);
    let displayed = WorkspaceEngine::start(owner(selected, 1)).0;
    owners.register(displayed).unwrap();
    let discovered = owners.exit_owners().unwrap();
    assert_eq!(discovered.len(), 1);
    assert_eq!(discovered[0].threads, std::slice::from_ref(&thread));
    assert_eq!(discovered[0].restore(), Some(hidden.clone()));
    assert!(matches!(
        owners.reserve_cleanup(&hidden),
        Err(OwnerError::Busy)
    ));

    let recovery = owners.begin_recovery(hidden.clone()).unwrap().unwrap();
    let resumed = owner(hidden.clone(), 2);
    let runtime = WorkspaceEngine::start(resumed.clone()).0;
    owners.register(runtime).unwrap();
    let history: Vec<HistoryTurn> = serde_json::from_value(json!([{
        "id": "turn", "status": "interrupted",
        "items": [{"type": "commandExecution", "id": "command", "status": "completed"}]
    }]))
    .unwrap();
    assert!(matches!(
        recovery.reconcile(&thread, &history),
        Err(OwnerError::Retired)
    ));
    assert_eq!(owners.exit_owners().unwrap().len(), 1);
    owners.retire(&resumed).unwrap();
    assert!(matches!(
        owners.reconcile_history(&resumed, &thread, &history),
        Err(OwnerError::Retired)
    ));
    let new_recovery = owners.begin_recovery(hidden.clone()).unwrap().unwrap();
    assert!(!new_recovery.reconcile(&thread, &history).unwrap());
    drop(new_recovery);
    assert!(owners.exit_owners().unwrap().is_empty());
    assert!(owners.reserve_cleanup(&hidden).is_ok());
}

#[test]
fn an_existing_draft_can_still_be_saved_after_its_checkout_is_replaced() {
    let root = tempfile::tempdir().unwrap();
    let original = checkout(root.path(), "selected");
    let state = AttachmentStore::open(&root.path().join("workspace.sqlite3")).unwrap();
    let draft = state
        .editable_thread_draft(&ThreadId("original".into()))
        .unwrap();
    let owners = RuntimeOwners::new(state.clone());
    fs::rename(original.canonical_path(), root.path().join("prior")).unwrap();
    fs::create_dir(root.path().join("selected")).unwrap();

    let _write = owners.acquire_write(&original).unwrap();
    state
        .save_editor_text(draft, "retained text".into())
        .unwrap();
    assert_eq!(
        state.read_editor_draft(draft).unwrap().text,
        "retained text"
    );
    assert!(matches!(
        owners.reserve_cleanup(&original),
        Err(OwnerError::Checkout(CheckoutError::Replaced(_)))
    ));
}
