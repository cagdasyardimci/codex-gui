use serde_json::json;

use crate::{
    codex::{HistoryTurn, ServerEvent},
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
};

use super::*;

fn owner(checkout: CheckoutIdentity) -> ConnectionIdentity {
    ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::new_v4()),
            checkout: Some(checkout),
        },
        generation: ConnectionGeneration(1),
    }
}

fn read(checkout: &CheckoutIdentity, changes: Value) -> ReportItem {
    ReportItem::read(checkout, &changes, true, false)
}

fn event(method: &str, params: Value) -> ServerEvent {
    ServerEvent::Notification {
        method: method.to_owned(),
        params,
    }
}

fn history(id: &str, started_at: i64, changes: Value) -> HistoryTurn {
    serde_json::from_value(json!({
        "id": id, "status": "completed", "startedAt": started_at,
        "items": [{"type": "fileChange", "id": "changes", "status": "completed", "changes": changes}],
    })).unwrap()
}

#[test]
fn exact_reports_cancel_reversals_and_preserve_owned_rename_paths() {
    let scratch = tempfile::tempdir().unwrap();
    let inner = scratch.path().join("owned");
    std::fs::create_dir(&inner).unwrap();
    let checkout = CheckoutIdentity::capture(&inner).unwrap();
    let item = read(
        &checkout,
        json!([
            {"path": "reverted.txt", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-A\n+B"},
            {"path": "reverted.txt", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-B\n+A"},
            {"path": "old λ.txt", "kind": {"type": "update", "move_path": "folder/../new λ.txt"}, "diff": ""},
            {"path": "new λ.txt", "kind": {"type": "update"}, "diff": "@@ -3 +3 @@\n-before\n+after"},
            {"path": "../outside.txt", "kind": {"type": "add"}, "diff": "outside\n"},
            {"path": "vacated.txt", "kind": {"type": "update", "move_path": scratch.path().join("outside.txt")}, "diff": ""},
        ]),
    );
    let turn = TurnEdits::build(&TurnId("turn".into()), [&item].into_iter(), false);
    assert_eq!(turn.view.quality, TurnEditQuality::Exact);
    assert_eq!(
        turn.view.totals,
        Some(EditTotals {
            additions: 1,
            deletions: 1
        })
    );
    let [file] = turn.files.as_slice() else {
        panic!("expected the owned rename only")
    };
    assert_eq!(file.before.as_deref(), Some(Path::new("old λ.txt")));
    assert_eq!(file.after.as_deref(), Some(Path::new("new λ.txt")));
    assert_eq!(file.totals, turn.view.totals.unwrap());
    let patch = turn.applicable_patch().unwrap();
    assert!(
        patch.contains("rename from \"old λ.txt\"") && patch.contains("rename to \"new λ.txt\"")
    );
    assert!(patch.contains("-before\n+after") && !patch.contains("outside"));
}

#[test]
fn incompatible_patches_preserve_reported_edits_without_an_applicable_patch() {
    let scratch = tempfile::tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let item = read(
        &checkout,
        json!([
            {"path": "file", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-A\n+B"},
            {"path": "file", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-X\n+C"},
        ]),
    );
    let turn = TurnEdits::build(&TurnId("turn".into()), [&item].into_iter(), false);
    assert_eq!(turn.view.quality, TurnEditQuality::Reported);
    assert_eq!(
        turn.view.totals,
        Some(EditTotals {
            additions: 2,
            deletions: 2
        })
    );
    assert_eq!(turn.files.len(), 2);
    assert!(turn.applicable_patch().is_none());
}

#[test]
fn inconsistent_hunk_positions_or_creation_ranges_remain_reported() {
    let scratch = tempfile::tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let item = read(
        &checkout,
        json!([
            {"path": "update", "kind": {"type": "update"}, "diff": "@@ -1 +1 @@\n-A\n+B\n@@ -3 +4 @@\n-C\n+D"},
            {"path": "add", "kind": {"type": "add"}, "diff": "@@ -1 +1 @@\n-A\n+B"},
        ]),
    );
    let turn = TurnEdits::build(&TurnId("turn".into()), [&item].into_iter(), false);
    assert_eq!(turn.view.quality, TurnEditQuality::Reported);
    assert_eq!(turn.files.len(), 2);
    assert!(turn.applicable_patch().is_none());
}

#[test]
fn retains_the_newest_known_identity_when_payloads_are_evicted_or_only_old_pages_are_loaded() {
    let scratch = tempfile::tempdir().unwrap();
    let identity = owner(CheckoutIdentity::capture(scratch.path()).unwrap());
    let mut reports = TurnEditReports::new(identity.clone());
    let thread = ThreadId("primary".into());
    assert!(reports.view(&thread).is_none());
    let new = history(
        "new",
        50,
        json!([{"path": "file", "kind": {"type": "add"}, "diff": "line\n"}]),
    );
    let older = history("older", 25, json!([]));
    reports.apply_latest_history(&identity, &thread, &[new]);
    reports.apply_latest_history(&identity, &thread, std::slice::from_ref(&older));
    assert_eq!(reports.view(&thread).unwrap().turn_id, "new");

    for index in 0..13 {
        reports.apply_latest_history(
            &identity,
            &ThreadId(format!("other-{index}")),
            std::slice::from_ref(&older),
        );
    }
    let missing = reports.view(&thread).unwrap();
    assert_eq!(missing.turn_id, "new");
    assert_eq!(missing.quality, TurnEditQuality::Missing);
    assert!(missing.totals.is_none() && reports.current(&thread).is_none());
    reports.apply_latest_history(&identity, &thread, &[older]);
    assert_eq!(reports.view(&thread), Some(missing));
}

#[test]
fn authoritative_empty_completion_uses_one_shared_result_and_ignores_late_or_retired_notifications()
{
    let scratch = tempfile::tempdir().unwrap();
    let identity = owner(CheckoutIdentity::capture(scratch.path()).unwrap());
    let mut retired = identity.clone();
    retired.generation = ConnectionGeneration(2);
    let mut reports = TurnEditReports::new(identity.clone());
    let thread = ThreadId("chat".into());
    reports.observe(
        &identity,
        &event(
            "turn/started",
            json!({"threadId": "chat", "turn": {"id": "active"}}),
        ),
    );
    let update = event(
        "item/fileChange/patchUpdated",
        json!({
            "threadId": "chat", "turnId": "active", "itemId": "edit",
            "changes": [{"path": "draft", "kind": {"type": "add"}, "diff": "initial\n"}],
        }),
    );
    reports.observe(&retired, &update);
    assert!(reports.current(&thread).is_none());
    reports.observe(&identity, &update);
    assert_eq!(
        reports.view(&thread).unwrap().quality,
        TurnEditQuality::Reported
    );
    let completed = event(
        "item/completed",
        json!({
            "threadId": "chat", "turnId": "active",
            "item": {"type": "fileChange", "id": "edit", "status": "completed", "changes": []},
        }),
    );
    reports.observe(&identity, &completed);
    let exact = reports.current(&thread).unwrap();
    assert_eq!(exact.view, reports.view(&thread).unwrap());
    assert_eq!(exact.view.quality, TurnEditQuality::Exact);
    assert_eq!(exact.view.totals, Some(EditTotals::default()));
    assert_eq!(exact.applicable_patch().as_deref(), Some(""));
    reports.observe(&identity, &completed);
    reports.observe(&identity, &update);
    let tentative = serde_json::from_value(json!({
        "id": "active", "status": "inProgress",
        "items": [{"type": "fileChange", "id": "edit", "status": "inProgress",
            "changes": [{"path": "draft", "kind": {"type": "add"}, "diff": "prior\n"}]}]
    }))
    .unwrap();
    reports.apply_latest_history(&identity, &thread, &[tentative]);
    assert!(Arc::ptr_eq(&exact, &reports.current(&thread).unwrap()));
    assert!(reports.current(&ThreadId("unrelated".into())).is_none());
}
