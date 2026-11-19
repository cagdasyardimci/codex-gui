use std::{fs, path::Path};

use tempfile::tempdir;

use super::*;
use crate::{
    checkout::CheckoutError,
    codex::{Account, BrowseError, CodexBrowser, ThreadActivity, TurnStatus},
    identity::ThreadId,
};

fn chat_row(checkout: &Path) -> Value {
    json!({
        "id": "chat-1",
        "cwd": checkout,
        "name": "Fixture",
        "preview": "Café",
        "createdAt": 10,
        "updatedAt": 20,
        "turns": [],
    })
}

#[tokio::test]
async fn browsing_uses_read_only_methods_and_checkout_scoped_chat_pages() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout.clone()));
    let browser = CodexBrowser::new(transport.client.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);

    time::timeout(DEADLINE, async {
        tokio::join!(
            async {
                let account = browser.account(DEADLINE).await.unwrap();
                assert!(matches!(account.account, Some(Account::ApiKey)));
                assert!(!account.requires_openai_auth);

                let models = browser.models(None, DEADLINE).await.unwrap();
                assert_eq!(models.data[0].id, "fixture-model");
                assert_eq!(models.next_cursor.as_deref(), Some("more-models"));

                let chats = browser.project_chats(false, None, DEADLINE).await.unwrap();
                assert_eq!(chats.data[0].preview, "Café");
                let cursor = chats.next_cursor.as_ref().unwrap();
                assert!(matches!(
                    browser.project_chats(true, Some(cursor), DEADLINE).await,
                    Err(BrowseError::CursorScope)
                ));

                let page = browser
                    .project_chats(false, Some(cursor), DEADLINE)
                    .await
                    .unwrap();
                assert!(page.data.is_empty());
                assert!(page.next_cursor.is_none());
            },
            async {
                let account = next_request(&mut server).await;
                assert_eq!(account["method"], "account/read");
                assert_eq!(account["params"], json!({"refreshToken": false}));
                respond(
                    &mut server_out,
                    account["id"].clone(),
                    json!({
                        "account": {"type": "apiKey"},
                        "requiresOpenaiAuth": false,
                    }),
                )
                .await;

                let models = next_request(&mut server).await;
                assert_eq!(models["method"], "model/list");
                assert_eq!(models["params"], json!({"limit": 100, "cursor": null}));
                respond(
                    &mut server_out,
                    models["id"].clone(),
                    json!({
                        "data": [{
                            "id": "fixture-model",
                            "model": "fixture-model",
                            "displayName": "Fixture",
                            "description": "Fixture model",
                            "hidden": false,
                            "isDefault": true,
                        }],
                        "nextCursor": "more-models",
                    }),
                )
                .await;

                let chats = next_request(&mut server).await;
                let expected = json!({
                    "cwd": checkout.canonical_path(),
                    "limit": 100,
                    "archived": false,
                    "cursor": null,
                    "sourceKinds": ["appServer", "cli", "vscode"],
                });
                assert_eq!(chats["method"], "thread/list");
                assert_eq!(chats["params"], expected);
                respond(
                    &mut server_out,
                    chats["id"].clone(),
                    json!({
                        "data": [chat_row(checkout.canonical_path())],
                        "nextCursor": "more-chats",
                    }),
                )
                .await;

                let next = next_request(&mut server).await;
                let mut expected = expected;
                expected["cursor"] = json!("more-chats");
                assert_eq!(next["method"], "thread/list");
                assert_eq!(next["params"], expected);
                respond(&mut server_out, next["id"].clone(), json!({"data": []})).await;
            }
        )
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn project_browsing_rejects_a_reply_containing_another_checkout() {
    let selected = tempdir().unwrap();
    let foreign = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(selected.path()).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout));
    let browser = CodexBrowser::new(transport.client.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);

    let (result, ()) = time::timeout(DEADLINE, async {
        tokio::join!(browser.project_chats(false, None, DEADLINE), async {
            let request = next_request(&mut server).await;
            assert_eq!(request["method"], "thread/list");
            respond(
                &mut server_out,
                request["id"].clone(),
                json!({"data": [chat_row(selected.path()), chat_row(foreign.path())]}),
            )
            .await;
        })
    })
    .await
    .unwrap();
    assert!(matches!(
        result,
        Err(BrowseError::Checkout(CheckoutError::Mismatch { .. }))
    ));
}

#[tokio::test]
async fn chat_summary_activity_and_history_use_separate_reads_and_scopes() {
    let scratch = tempdir().unwrap();
    let checkout = CheckoutIdentity::capture(scratch.path()).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(checkout.clone()));
    let connection = transport.client.identity().clone();
    let browser = CodexBrowser::new(transport.client.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let thread = ThreadId("chat-1".into());

    time::timeout(DEADLINE, async {
        tokio::join!(
            async {
                let summary = browser.thread_summary(&thread, DEADLINE).await.unwrap();
                assert!(matches!(
                    summary.for_selection(&connection, &thread).unwrap().activity,
                    ThreadActivity::Active { ref flags } if flags == &["waitingOnApproval"]
                ));

                let statuses = browser.turn_statuses(&summary, None, DEADLINE).await.unwrap();
                let page = statuses.for_selection(&connection, &thread).unwrap();
                assert_eq!(page.data[0].status, TurnStatus::InProgress);
                assert_eq!(page.data[0].id.0, "turn-current");
                let status_cursor = page.next_cursor.as_ref();

                assert!(matches!(
                    browser.history(&summary, status_cursor, DEADLINE).await,
                    Err(BrowseError::CursorScope)
                ));
                let history = browser.history(&summary, None, DEADLINE).await.unwrap();
                let history_page = history.for_selection(&connection, &thread).unwrap();
                assert_eq!(history_page.data[0].items[0]["text"], "完整 history");

                let older = browser
                    .history(&summary, history_page.next_cursor.as_ref(), DEADLINE)
                    .await
                    .unwrap();
                let older = older.for_selection(&connection, &thread).unwrap();
                assert_eq!(older.data[0].activity.status, TurnStatus::Completed);
                assert!(older.next_cursor.is_none());

                let other = ThreadId("chat-2".into());
                assert!(matches!(
                    history.for_selection(&connection, &other),
                    Err(BrowseError::StaleChatRead)
                ));
                let mut reconnected = connection.clone();
                reconnected.generation = ConnectionGeneration(2);
                assert!(matches!(
                    history.for_selection(&reconnected, &thread),
                    Err(BrowseError::StaleChatRead)
                ));

                let second = browser.thread_summary(&other, DEADLINE).await.unwrap();
                assert!(matches!(
                    browser.turn_statuses(&second, status_cursor, DEADLINE).await,
                    Err(BrowseError::CursorScope)
                ));
            },
            async {
                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/read");
                assert_eq!(request["params"], json!({"threadId": "chat-1", "includeTurns": false}));
                let mut row = chat_row(checkout.canonical_path());
                row["status"] = json!({"type": "active", "activeFlags": ["waitingOnApproval"]});
                respond(&mut server_out, request["id"].clone(), json!({"thread": row})).await;

                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/turns/list");
                assert_eq!(request["params"], json!({
                    "threadId": "chat-1", "itemsView": "notLoaded", "sortDirection": "desc",
                    "cursor": null, "limit": 100,
                }));
                respond(&mut server_out, request["id"].clone(), json!({
                    "data": [{"id": "turn-current", "status": "inProgress", "itemsView": "notLoaded", "items": []}],
                    "nextCursor": "more-statuses",
                })).await;

                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/turns/list");
                assert_eq!(request["params"], json!({
                    "threadId": "chat-1", "itemsView": "full", "sortDirection": "desc",
                    "cursor": null, "limit": 20,
                }));
                respond(&mut server_out, request["id"].clone(), json!({
                    "data": [{"id": "turn-current", "status": "inProgress", "items": [
                        {"type": "agentMessage", "id": "item-current", "text": "完整 history"}
                    ]}],
                    "nextCursor": "more-history",
                })).await;

                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/turns/list");
                assert_eq!(request["params"], json!({
                    "threadId": "chat-1", "itemsView": "full", "sortDirection": "desc",
                    "cursor": "more-history", "limit": 20,
                }));
                respond(&mut server_out, request["id"].clone(), json!({
                    "data": [{"id": "turn-old", "status": "completed", "items": []}],
                })).await;

                let request = next_request(&mut server).await;
                assert_eq!(request["method"], "thread/read");
                assert_eq!(request["params"], json!({"threadId": "chat-2", "includeTurns": false}));
                row["id"] = json!("chat-2");
                row["status"] = json!({"type": "idle"});
                respond(&mut server_out, request["id"].clone(), json!({"thread": row})).await;
            }
        )
    }).await.unwrap();
}

#[tokio::test]
async fn summary_rejects_a_checkout_replaced_between_request_and_reply() {
    let scratch = tempdir().unwrap();
    let path = scratch.path().join("checkout");
    fs::create_dir(&path).unwrap();
    let identity = CheckoutIdentity::capture(&path).unwrap();
    let (transport, server_in, mut server_out) = transport_for(4096, 1, Some(identity));
    let browser = CodexBrowser::new(transport.client.clone());
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let thread = ThreadId("chat-1".into());

    let (result, ()) = time::timeout(DEADLINE, async {
        tokio::join!(browser.thread_summary(&thread, DEADLINE), async {
            let request = next_request(&mut server).await;
            fs::rename(&path, scratch.path().join("old checkout")).unwrap();
            fs::create_dir(&path).unwrap();
            let mut row = chat_row(&path);
            row["status"] = json!({"type": "idle"});
            respond(
                &mut server_out,
                request["id"].clone(),
                json!({"thread": row}),
            )
            .await;
        })
    })
    .await
    .unwrap();
    assert!(matches!(
        result,
        Err(BrowseError::Checkout(CheckoutError::Replaced(_)))
    ));
}
