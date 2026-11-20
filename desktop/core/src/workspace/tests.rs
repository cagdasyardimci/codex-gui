use serde_json::json;
use tempfile::{TempDir, tempdir};
use uuid::Uuid;

use super::*;
use crate::{
    checkout::CheckoutIdentity,
    identity::{CheckoutSessionId, ConnectionGeneration, WorkspaceIdentity},
    storage::{
        attachments::AttachmentStore,
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

fn admission(operation: OperationIdentity, draft: DraftId) -> WorkspaceAction {
    WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
        operation,
        draft: SendDraft {
            id: draft,
            revision: DraftRevision::INITIAL,
            text: "fixture input".into(),
            context: Vec::new(),
            attachments: Vec::new(),
        },
        settings: SendSettings::default(),
    }))
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
        .apply(admission(first.clone(), draft(1)))
        .await
        .unwrap();
    let prepared = effects.try_recv().unwrap();
    assert_eq!(prepared.intent.operation, first);
    assert_eq!(prepared.intent.draft.id, draft(1));
    engine
        .apply(admission(other.clone(), draft(2)))
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
        .apply(admission(accepted.clone(), draft(1)))
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
        .apply(admission(operation(&reconnected, 2), draft(1)))
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
            .apply(admission(operation(&connection, index), draft(index)))
            .await
            .unwrap();
    }
    let before = engine.snapshot();
    assert_eq!(
        engine
            .apply(admission(operation(&connection, 100), draft(100)))
            .await,
        Err(WorkspaceError::EffectQueueFull)
    );
    assert!(Arc::ptr_eq(&engine.snapshot(), &before));
}

#[tokio::test]
async fn send_captures_visible_edits_settings_and_leases_before_preparation() {
    let (checkout, connection) = connected();
    let path = checkout.path().join("workspace.sqlite3");
    let mut database = open_workspace_database(&path).unwrap();
    let draft_id = draft(1);
    let previous = DraftRevision::INITIAL;
    save_draft(
        &mut database,
        draft_id,
        None,
        previous,
        &DraftPatch {
            text: Some("older persisted draft".into()),
            context: None,
        },
    )
    .unwrap();
    let attachment_store = AttachmentStore::open(&path).unwrap();
    let attachment = attachment_store
        .stage(b"capture the image".as_slice())
        .unwrap();
    let attachment_path = attachment.path();
    let attachment_id = attachment.id();
    let (engine, mut effects) = WorkspaceEngine::start(connection.clone());
    let operation = operation(&connection, 1);
    let visible_revision = previous.next().unwrap();
    let mut settings = SendSettings {
        model: Some("captured model".into()),
        reasoning_effort: Some("high".into()),
        service_tier: Some("priority".into()),
        approval_policy: Some(json!("on-request")),
        approvals_reviewer: Some("user".into()),
        sandbox_policy: Some(json!({"type": "workspaceWrite"})),
        collaboration_mode: Some(json!({"mode": "default"})),
    };
    let captured_settings = settings.clone();

    engine
        .apply(WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
            operation: operation.clone(),
            draft: SendDraft {
                id: draft_id,
                revision: visible_revision,
                text: "  unsaved café\n".into(),
                context: vec![json!({"type": "file", "path": "shown.txt"})],
                attachments: vec![attachment],
            },
            settings: settings.clone(),
        })))
        .await
        .unwrap();
    settings.model = Some("next selection".into());
    let effect = effects.try_recv().unwrap();
    assert_eq!(effect.intent.operation, operation);
    assert_eq!(effect.intent.draft.revision, visible_revision);
    assert_eq!(effect.intent.draft.text, "  unsaved café\n");
    assert_eq!(effect.intent.draft.context[0]["path"], "shown.txt");
    assert_eq!(effect.intent.settings, captured_settings);
    assert_ne!(effect.intent.settings, settings);
    assert_eq!(effect.intent.draft.attachments[0].id(), attachment_id);
    assert_eq!(
        read_draft(&database, draft_id).unwrap().unwrap().text,
        "older persisted draft"
    );

    drop(effect);
    attachment_store.collect().unwrap();
    assert!(attachment_path.is_file());
    engine
        .apply(WorkspaceAction::PreparationFailed { operation })
        .await
        .unwrap();
    attachment_store.collect().unwrap();
    assert!(!attachment_path.exists());
}

#[tokio::test]
async fn an_attachment_can_supply_the_only_content_for_send() {
    let (checkout, connection) = connected();
    let attachment_store =
        AttachmentStore::open(&checkout.path().join("workspace.sqlite3")).unwrap();
    let (engine, mut effects) = WorkspaceEngine::start(connection.clone());
    let image = attachment_store.stage(b"image".as_slice()).unwrap();
    let image_id = image.id();
    engine
        .apply(WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
            operation: operation(&connection, 1),
            draft: SendDraft {
                id: draft(1),
                revision: DraftRevision::INITIAL,
                text: String::new(),
                context: Vec::new(),
                attachments: vec![image],
            },
            settings: SendSettings::default(),
        })))
        .await
        .unwrap();
    assert_eq!(
        effects.try_recv().unwrap().intent.draft.attachments[0].id(),
        image_id
    );
}
