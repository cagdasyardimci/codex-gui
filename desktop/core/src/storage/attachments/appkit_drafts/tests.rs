use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::json;
use tempfile::{TempDir, tempdir};

use super::*;
use crate::{
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, TurnId, WorkspaceIdentity,
    },
    storage::{
        attachments::{JournalOutcome, LegacyQueueStatus, SubmissionAcknowledgement},
        drafts::{DraftPatch, save_draft},
    },
};

const IMAGE_NAME: &str = "A0000000-0000-0000-0000-000000000001.png";
const PNG: &str = "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6390d071fa0f00026c018670e9bcb00000000049454e44ae426082";

struct Fixture {
    scratch: TempDir,
    checkout: CheckoutIdentity,
    original: PathBuf,
    copied: PathBuf,
    preferences: PathBuf,
    database: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let scratch = tempdir().unwrap();
        let project = scratch.path().join("Café project");
        let original = scratch.path().join("original/DraftImages");
        let copied = scratch.path().join("staged/DraftImages");
        fs::create_dir(&project).unwrap();
        fs::create_dir_all(&copied).unwrap();
        let checkout = CheckoutIdentity::capture(&project).unwrap();
        let preferences = scratch.path().join("staged/preferences.plist");
        let database = scratch.path().join("workspace.sqlite3");
        Self {
            scratch,
            checkout,
            original,
            copied,
            preferences,
            database,
        }
    }

    fn source(&self) -> AppKitDraftCopy<'_> {
        AppKitDraftCopy {
            preferences: &self.preferences,
            original_images: &self.original,
            copied_images: &self.copied,
        }
    }

    fn image(&self) -> Value {
        json!({
            "id":"image-1", "kind":"image", "title":"Screenshot",
            "path":self.original.join(IMAGE_NAME),
            "imageAnnotations":[{"id":"annotation-1","x":0.25,"y":0.75,"text":"Café\ncomment"}]
        })
    }

    fn copied_png(&self) -> Vec<u8> {
        let bytes = hex::decode(PNG).unwrap();
        fs::write(self.copied.join(IMAGE_NAME), &bytes).unwrap();
        bytes
    }
}

#[test]
fn appkit_queue_import_preserves_paused_order_server_receipts_and_independent_drafts() {
    use queues::AppKitQueueImport;

    let fixture = Fixture::new();
    let png = fixture.copied_png();
    let checkout = &fixture.checkout;
    let project = checkout.canonical_path().to_str().unwrap();
    let thread = ThreadId("queue-thread".into());
    let legacy = ThreadId("legacy-thread".into());
    let image = fixture.image();
    let ids: Vec<_> = (1..=5).map(Uuid::from_u128).collect();
    let raw = |index: usize| ids[index].to_string().to_ascii_uppercase();
    let mut preferences = plist::Dictionary::new();
    let mut queues = plist::Dictionary::new();
    let captured = json!([
        {"type":"text","text":"Exact detached input"},
        {"type":"localImage","path":fixture.original.join(IMAGE_NAME)}
    ]);
    queues.insert("thread:queue-thread".into(), PlistValue::Data(serde_json::to_vec(&json!({
        "messages":[
            {"id":raw(0),"text":"Waiting next","context":[image],"modelID":"saved-model","effort":"high",
             "preferences":{"approvalMode":"approveForMe","fastMode":true},"serviceTier":"fast"},
            {"id":raw(1),"text":"Server content","context":[image],"serverID":"owned-server-id"},
            {"id":raw(2),"text":"Uncertain","context":[],"enqueueUncertain":true},
        ],
        "edit":{"position":0,"message":{
            "id":raw(3),"text":"Previous editor input","context":[image],"steeringPhase":"ready",
            "steeringInputJSON":STANDARD.encode(serde_json::to_vec(&captured).unwrap())
        }}
    })).unwrap()));
    queues.insert(
        "thread:legacy-thread".into(),
        PlistValue::Data(
            serde_json::to_vec(&json!([
                {"id":raw(4),"text":"Older array format","context":[]}
            ]))
            .unwrap(),
        ),
    );
    let mut projects = plist::Dictionary::new();
    projects.insert(project.to_owned(), PlistValue::Dictionary(queues));
    preferences.insert(
        "CodexGUI.queuedMessages".into(),
        PlistValue::Dictionary(projects),
    );
    preferences.insert(
        "CodexGUI.queueingEnabled".into(),
        plist::to_value(
            &json!({(project):{"thread:queue-thread":false,"thread:legacy-thread":false}}),
        )
        .unwrap(),
    );
    plist::to_file_binary(&fixture.preferences, &preferences).unwrap();
    let untouched = fs::read(&fixture.preferences).unwrap();
    let owner = ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::new_v4()),
            checkout: Some(checkout.clone()),
        },
        generation: ConnectionGeneration(3),
    };
    let store = AttachmentStore::open(&fixture.database).unwrap();
    let draft = store.editable_thread_draft(&thread).unwrap();
    store
        .save_editor_text(draft, "A newer independent draft".into())
        .unwrap();
    store.set_queue_enabled(checkout, &thread, true).unwrap();
    assert_eq!(
        store
            .import_appkit_queues(fixture.source(), checkout)
            .unwrap(),
        AppKitQueueImport {
            paused_entries: 3,
            server_receipts: 2,
            preserved_entries: 0,
            preferences: 1,
        }
    );
    assert!(store.queue_enabled(checkout, &thread).unwrap());
    assert!(!store.queue_enabled(checkout, &legacy).unwrap());
    assert_eq!(
        store.read_editor_draft(draft).unwrap().text,
        "A newer independent draft"
    );
    let pending = store.pending_submissions(checkout).unwrap();
    assert_eq!(pending.len(), 2);
    assert_eq!(pending[0].queued_id.as_deref(), Some("owned-server-id"));
    assert_eq!(pending[1].queued_id, None);
    let queue = store.legacy_queue(checkout, &thread, &owner).unwrap();
    assert_eq!(
        queue.iter().map(|entry| entry.id.0).collect::<Vec<_>>(),
        [ids[3], ids[0]]
    );
    assert!(
        queue
            .iter()
            .all(|entry| entry.status == LegacyQueueStatus::Paused)
    );
    assert_eq!(queue[0].input[0]["text"], "Exact detached input");
    assert_eq!(
        queue[1].input[0]["text"],
        "Waiting next\n\nImage 1:\n1. (x: 25%, y: 75%) Café\ncomment"
    );
    let owned = PathBuf::from(queue[0].input[1]["path"].as_str().unwrap());
    assert_eq!(queue[1].input[1]["path"], json!(owned));
    assert_eq!(fs::read(&owned).unwrap(), png);
    assert!(
        store
            .claim_legacy_dispatch(checkout, &thread, &owner, None)
            .unwrap()
            .is_none()
    );
    assert_eq!(
        store
            .acknowledge_submission(
                RequestId(ids[1]),
                &thread,
                JournalOutcome::Accepted(TurnId("observed".into())),
                checkout,
            )
            .unwrap(),
        SubmissionAcknowledgement::Accepted {
            retired_draft: false
        }
    );
    drop(store);
    let store = AttachmentStore::open(&fixture.database).unwrap();
    fs::remove_file(fixture.copied.join(IMAGE_NAME)).unwrap();
    assert_eq!(
        store
            .import_appkit_queues(fixture.source(), checkout)
            .unwrap(),
        AppKitQueueImport {
            paused_entries: 0,
            server_receipts: 0,
            preserved_entries: 5,
            preferences: 0,
        }
    );
    assert!(owned.is_file());
    assert_eq!(fs::read(&fixture.preferences).unwrap(), untouched);
    assert!(
        store
            .claim_legacy_dispatch(checkout, &thread, &owner, None)
            .unwrap()
            .is_none()
    );
    let send = store
        .claim_legacy_dispatch(checkout, &thread, &owner, Some(RequestId(ids[3])))
        .unwrap()
        .unwrap();
    assert_eq!(send.id, RequestId(ids[3]));
    assert_eq!(send.request["input"][0]["text"], "Exact detached input");
    let db = open_workspace_database(&fixture.database).unwrap();
    let captured: String = db
        .query_row(
            "SELECT request FROM submissions WHERE id = ?1",
            [ids[0].as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap();
    let captured: Value = serde_json::from_str(&captured).unwrap();
    assert_eq!(captured["model"], "saved-model");
    assert_eq!(captured["effort"], "high");
    assert_eq!(captured["serviceTierForTurn"], "fast");
    assert_eq!(captured["approvalsReviewer"], "auto_review");
}

#[test]
fn copied_drafts_and_sent_references_share_owned_image_bytes_across_reopen() {
    let fixture = Fixture::new();
    let png = fixture.copied_png();
    let scope = fixture.checkout.canonical_path().to_str().unwrap();
    let image = fixture.image();
    let external = json!({
        "id":"external-1","kind":"image","title":"Existing file","path":fixture.scratch.path().join("external.png")
    });
    let mut preferences = plist::Dictionary::new();
    preferences.insert(
        "CodexGUI.drafts".into(),
        plist::to_value(&json!({(scope):{"new-chat":"unsent café","thread:thread-1":"next turn"}}))
            .unwrap(),
    );
    preferences.insert(
        "CodexGUI.draftContext".into(),
        PlistValue::Data(
            serde_json::to_vec(&json!({(scope):{"thread:thread-1":[image, external]}})).unwrap(),
        ),
    );
    preferences.insert(
        "CodexGUI.sentReferences".into(),
        PlistValue::Data(
            serde_json::to_vec(&json!([{"projectPath":scope,"threadID":"thread-1","item":image}]))
                .unwrap(),
        ),
    );
    plist::to_file_binary(&fixture.preferences, &preferences).unwrap();
    let original_preferences = fs::read(&fixture.preferences).unwrap();
    let store = AttachmentStore::open(&fixture.database).unwrap();
    assert_eq!(
        store
            .import_appkit_drafts(fixture.source(), &fixture.checkout)
            .unwrap(),
        AppKitDraftImport {
            imported_drafts: 2,
            preserved_drafts: 0,
            imported_sent_references: 1,
        }
    );
    let before = store.imported_appkit_drafts(&fixture.checkout).unwrap();
    drop(store);

    let store = AttachmentStore::open(&fixture.database).unwrap();
    assert_eq!(
        store.imported_appkit_drafts(&fixture.checkout).unwrap(),
        before
    );
    let thread = ThreadId("thread-1".into());
    let existing = before
        .iter()
        .find(|draft| draft.thread.as_ref() == Some(&thread))
        .unwrap();
    let new = before.iter().find(|draft| draft.thread.is_none()).unwrap();
    let mut database = open_workspace_database(&fixture.database).unwrap();
    assert_eq!(
        read_draft(&database, new.id).unwrap().unwrap().text,
        "unsent café"
    );
    let draft = read_draft(&database, existing.id).unwrap().unwrap();
    assert_eq!(draft.text, "next turn");
    assert_eq!(
        draft.context[0]["imageAnnotations"],
        image["imageAnnotations"]
    );
    assert_eq!(draft.context[1], external);
    let owned = PathBuf::from(draft.context[0]["path"].as_str().unwrap());
    assert_eq!(fs::read(&owned).unwrap(), png);
    let sent = store
        .imported_appkit_sent_references(&fixture.checkout, &thread)
        .unwrap();
    assert_eq!(sent[0].item, draft.context[0]);
    assert_eq!(
        sent[0].original_image_path.as_deref(),
        Some(fixture.original.join(IMAGE_NAME).as_path())
    );

    save_draft(
        &mut database,
        existing.id,
        Some(draft.revision),
        draft.revision.next().unwrap(),
        &DraftPatch {
            text: Some("newer Tauri draft".into()),
            context: Some(Vec::new()),
        },
    )
    .unwrap();
    store.replace_draft_references(existing.id, &[]).unwrap();
    store.collect().unwrap();
    assert!(owned.exists(), "the sent reference still owns the blob");
    assert_eq!(
        store
            .import_appkit_drafts(fixture.source(), &fixture.checkout)
            .unwrap(),
        AppKitDraftImport {
            imported_drafts: 0,
            preserved_drafts: 2,
            imported_sent_references: 0,
        }
    );
    assert_eq!(
        read_draft(&database, existing.id).unwrap().unwrap().text,
        "newer Tauri draft"
    );
    assert_eq!(
        fs::read(&fixture.preferences).unwrap(),
        original_preferences
    );
    assert_eq!(fs::read(fixture.copied.join(IMAGE_NAME)).unwrap(), png);
}

#[test]
fn missing_legacy_image_leaves_the_copied_draft_retryable() {
    let fixture = Fixture::new();
    let scope = fixture.checkout.canonical_path().to_str().unwrap();
    let mut preferences = plist::Dictionary::new();
    preferences.insert("recentProject".into(), PlistValue::String(scope.into()));
    preferences.insert("draft".into(), PlistValue::String("legacy draft".into()));
    preferences.insert(
        "CodexGUI.sentReferences".into(),
        PlistValue::Data(
            serde_json::to_vec(&json!({(scope):{"thread:legacy":[fixture.image()]}})).unwrap(),
        ),
    );
    plist::to_file_xml(&fixture.preferences, &preferences).unwrap();
    let store = AttachmentStore::open(&fixture.database).unwrap();
    assert!(matches!(
        store.import_appkit_drafts(fixture.source(), &fixture.checkout),
        Err(AppKitDraftError::Disk(error)) if error.kind() == io::ErrorKind::NotFound
    ));
    assert!(
        store
            .imported_appkit_drafts(&fixture.checkout)
            .unwrap()
            .is_empty()
    );
    fixture.copied_png();
    assert_eq!(
        store
            .import_appkit_drafts(fixture.source(), &fixture.checkout)
            .unwrap(),
        AppKitDraftImport {
            imported_drafts: 1,
            preserved_drafts: 0,
            imported_sent_references: 1,
        }
    );
    let drafts = store.imported_appkit_drafts(&fixture.checkout).unwrap();
    let database = open_workspace_database(&fixture.database).unwrap();
    assert!(drafts[0].thread.is_none());
    assert_eq!(
        read_draft(&database, drafts[0].id).unwrap().unwrap().text,
        "legacy draft"
    );
    assert_eq!(
        store
            .imported_appkit_sent_references(&fixture.checkout, &ThreadId("legacy".into()))
            .unwrap()[0]
            .item["id"],
        "image-1"
    );
}
