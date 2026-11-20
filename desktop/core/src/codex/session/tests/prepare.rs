use tempfile::tempdir;

use super::*;
use crate::{
    identity::{OperationIdentity, RequestId, ThreadId},
    storage::{
        attachments::AttachmentStore,
        drafts::{DraftId, DraftPatch, DraftRevision, read_draft, save_draft},
        open_workspace_database,
    },
    workspace::{
        NavigationRow, NavigationTarget, PrepareError, SendDraft, SendIntent, SendSettings,
        WorkspaceAction, WorkspaceEngine, WorkspaceError,
    },
};

#[tokio::test]
async fn thread_start_binds_the_original_visible_draft_and_attachment() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let db_path = scratch.path().join("workspace.sqlite3");
    let store = AttachmentStore::open(&db_path).unwrap();
    let mut database = open_workspace_database(&db_path).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout.clone()));
    let client = &transport.client;
    let connection = client.identity();
    let (engine, mut effects) = WorkspaceEngine::start(connection.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let original = DraftId(Uuid::from_u128(10));
    let newer = DraftId(Uuid::from_u128(11));
    let attachment = store.stage("attachment".as_bytes()).unwrap();
    let attachment_path = attachment.path();
    let initial = DraftRevision::INITIAL;
    let visible = initial.next().unwrap();
    save_draft(
        &mut database,
        original,
        None,
        initial,
        &DraftPatch {
            text: Some("before debounce".into()),
            context: None,
        },
    )
    .unwrap();
    engine
        .apply(first_message(
            connection,
            SendDraft {
                id: original,
                revision: visible,
                text: "  visible café\n".into(),
                context: vec![json!({"path": "file with spaces.txt"})],
                attachments: vec![attachment],
            },
        ))
        .await
        .unwrap();
    let effect = effects.try_recv().unwrap();
    let thread = ThreadId("assigned-thread".into());
    let (prepared, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.prepare_thread(effect, client, &store, DEADLINE),
            async {
                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/start");
                assert_eq!(request["params"], json!({"cwd": checkout.canonical_path()}));
                save_draft(
                    &mut database,
                    newer,
                    None,
                    initial,
                    &DraftPatch {
                        text: Some("other draft".into()),
                        context: None,
                    },
                )
                .unwrap();
                engine
                    .apply(first_message(
                        connection,
                        SendDraft {
                            id: newer,
                            revision: initial,
                            text: "other draft".into(),
                            context: Vec::new(),
                            attachments: Vec::new(),
                        },
                    ))
                    .await
                    .unwrap();
                let cwd = checkout.canonical_path();
                respond(
                    &mut server_out,
                    request["id"].clone(),
                    json!({
                        "cwd": cwd, "thread": { "id": thread.0, "cwd": cwd }
                    }),
                )
                .await;
            }
        )
    })
    .await
    .unwrap();
    assert_eq!(prepared.unwrap(), thread);
    assert_eq!(
        engine.snapshot().rows,
        [
            NavigationRow {
                draft: original,
                target: NavigationTarget::Thread(thread.clone())
            },
            NavigationRow {
                draft: newer,
                target: NavigationTarget::Preparing(RequestId(newer.0))
            },
        ]
    );
    let reopened = open_workspace_database(&db_path).unwrap();
    let bound: [u8; 16] = reopened
        .query_row(
            "SELECT draft_id FROM thread_drafts WHERE thread_id = ?1",
            [&thread.0],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(bound, *original.0.as_bytes());
    let saved = read_draft(&reopened, original).unwrap().unwrap();
    assert_eq!(saved.revision, visible);
    assert_eq!(saved.text, "  visible café\n");
    assert_eq!(saved.context, [json!({"path": "file with spaces.txt"})]);
    assert_eq!(
        read_draft(&reopened, newer).unwrap().unwrap().text,
        "other draft"
    );
    store.collect().unwrap();
    assert!(attachment_path.is_file());
}

#[tokio::test]
async fn a_late_thread_start_cannot_bind_after_connection_retirement() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let db_path = scratch.path().join("workspace.sqlite3");
    let store = AttachmentStore::open(&db_path).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout.clone()));
    let client = &transport.client;
    let connection = client.identity();
    let (engine, mut effects) = WorkspaceEngine::start(connection.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let draft = DraftId(Uuid::from_u128(19));
    engine
        .apply(first_message(
            connection,
            SendDraft {
                id: draft,
                revision: DraftRevision::INITIAL,
                text: "retired".into(),
                context: Vec::new(),
                attachments: Vec::new(),
            },
        ))
        .await
        .unwrap();
    let effect = effects.try_recv().unwrap();
    let (prepared, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            engine.prepare_thread(effect, client, &store, DEADLINE),
            async {
                let request = next_request(&mut server).await;
                let mut replacement = connection.clone();
                replacement.generation = ConnectionGeneration(2);
                engine
                    .apply(WorkspaceAction::ReplaceConnection {
                        expected: connection.clone(),
                        replacement,
                    })
                    .await
                    .unwrap();
                let cwd = checkout.canonical_path();
                respond(
                    &mut server_out,
                    request["id"].clone(),
                    json!({
                        "cwd": cwd, "thread": { "id": "retired", "cwd": cwd }
                    }),
                )
                .await;
            }
        )
    })
    .await
    .unwrap();
    assert!(matches!(
        prepared,
        Err(PrepareError::Workspace(WorkspaceError::Retired))
    ));
    assert!(engine.snapshot().rows.is_empty());
    let database = open_workspace_database(&db_path).unwrap();
    assert!(read_draft(&database, draft).unwrap().is_none());
    let bindings: i64 = database
        .query_row("SELECT COUNT(*) FROM thread_drafts", [], |row| row.get(0))
        .unwrap();
    assert_eq!(bindings, 0);
}

fn first_message(connection: &ConnectionIdentity, draft: SendDraft) -> WorkspaceAction {
    WorkspaceAction::AdmitFirstMessage(Arc::new(SendIntent {
        operation: OperationIdentity {
            connection: connection.clone(),
            request: RequestId(draft.id.0),
        },
        draft,
        settings: SendSettings::default(),
    }))
}
