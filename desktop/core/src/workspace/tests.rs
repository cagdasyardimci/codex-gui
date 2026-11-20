use tempfile::{TempDir, tempdir};
use uuid::Uuid;

use super::*;
use crate::{
    checkout::CheckoutIdentity,
    identity::{CheckoutSessionId, ConnectionGeneration, WorkspaceIdentity},
    storage::{
        drafts::{DraftPatch, DraftRevision, read_draft, save_draft},
        open_workspace_database,
    },
};

fn connected() -> (TempDir, ConnectionIdentity) {
    let checkout = tempdir().unwrap();
    let connection = ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::from_u128(1)),
            checkout: Some(CheckoutIdentity::capture(checkout.path()).unwrap()),
        },
        generation: ConnectionGeneration(1),
    };
    (checkout, connection)
}

fn operation(connection: &ConnectionIdentity, index: u128) -> OperationIdentity {
    OperationIdentity {
        connection: connection.clone(),
        request: RequestId(Uuid::from_u128(index)),
    }
}

fn draft(index: u128) -> DraftId {
    DraftId(Uuid::from_u128(index))
}

#[tokio::test]
async fn thread_assignment_adopts_an_accepted_row_and_keeps_the_draft() {
    let (checkout, connection) = connected();
    let mut database = open_workspace_database(&checkout.path().join("workspace.sqlite3")).unwrap();
    let first = operation(&connection, 1);
    let other = operation(&connection, 2);
    for (id, text) in [(draft(1), "first text"), (draft(2), "separate text")] {
        save_draft(
            &mut database,
            id,
            None,
            DraftRevision::INITIAL,
            &DraftPatch {
                text: Some(text.into()),
                context: None,
            },
        )
        .unwrap();
    }

    let (engine, mut effects) = WorkspaceEngine::start(connection);
    engine
        .apply(WorkspaceAction::AdmitFirstMessage {
            operation: first.clone(),
            draft: draft(1),
        })
        .await
        .unwrap();
    assert_eq!(
        effects.try_recv().unwrap(),
        PrepareThread {
            operation: first.clone(),
            draft: draft(1)
        }
    );
    engine
        .apply(WorkspaceAction::AdmitFirstMessage {
            operation: other.clone(),
            draft: draft(2),
        })
        .await
        .unwrap();
    let thread = ThreadId("assigned-thread".into());
    assert_eq!(
        engine.snapshot().rows[0].target,
        NavigationTarget::Preparing(first.request)
    );
    engine
        .apply(WorkspaceAction::ThreadPrepared {
            operation: first,
            thread: thread.clone(),
        })
        .await
        .unwrap();
    assert_eq!(
        engine.snapshot().rows,
        [
            NavigationRow {
                draft: draft(1),
                target: NavigationTarget::Thread(thread)
            },
            NavigationRow {
                draft: draft(2),
                target: NavigationTarget::Preparing(other.request)
            }
        ]
    );
    engine
        .apply(WorkspaceAction::PreparationFailed { operation: other })
        .await
        .unwrap();
    assert_eq!(engine.snapshot().rows.len(), 1);
    for (id, text) in [(draft(1), "first text"), (draft(2), "separate text")] {
        assert_eq!(read_draft(&database, id).unwrap().unwrap().text, text);
    }
}

#[tokio::test]
async fn reopened_sessions_and_retired_connections_cannot_adopt_a_row() {
    let (_checkout, original) = connected();
    let (engine, _effects) = WorkspaceEngine::start(original.clone());
    let accepted = operation(&original, 1);
    engine
        .apply(WorkspaceAction::AdmitFirstMessage {
            operation: accepted.clone(),
            draft: draft(1),
        })
        .await
        .unwrap();
    let mut other_session = original.clone();
    other_session.workspace.session = CheckoutSessionId(Uuid::from_u128(2));
    assert_eq!(
        engine
            .apply(WorkspaceAction::ThreadPrepared {
                operation: operation(&other_session, 1),
                thread: ThreadId("from another session".into()),
            })
            .await,
        Err(WorkspaceError::Retired)
    );
    assert_eq!(engine.snapshot().revision, 1);

    let mut reconnected = original.clone();
    reconnected.generation = ConnectionGeneration(2);
    engine
        .apply(WorkspaceAction::ReplaceConnection {
            expected: original,
            replacement: reconnected.clone(),
        })
        .await
        .unwrap();
    engine
        .apply(WorkspaceAction::AdmitFirstMessage {
            operation: operation(&reconnected, 2),
            draft: draft(1),
        })
        .await
        .unwrap();
    assert_eq!(
        engine
            .apply(WorkspaceAction::PreparationFailed {
                operation: accepted
            })
            .await,
        Err(WorkspaceError::Retired)
    );
    assert_eq!(
        engine.snapshot().rows[0].target,
        NavigationTarget::Preparing(operation(&reconnected, 2).request)
    );
}

#[tokio::test]
async fn an_unreservable_effect_leaves_the_published_state_intact() {
    let (_checkout, connection) = connected();
    let (engine, _undrained_effects) = WorkspaceEngine::start(connection.clone());
    for index in 0..EFFECT_CAPACITY as u128 {
        engine
            .apply(WorkspaceAction::AdmitFirstMessage {
                operation: operation(&connection, index),
                draft: draft(index),
            })
            .await
            .unwrap();
    }
    let before = engine.snapshot();
    assert_eq!(
        engine
            .apply(WorkspaceAction::AdmitFirstMessage {
                operation: operation(&connection, 100),
                draft: draft(100),
            })
            .await,
        Err(WorkspaceError::EffectQueueFull)
    );
    assert!(Arc::ptr_eq(&engine.snapshot(), &before));
}
