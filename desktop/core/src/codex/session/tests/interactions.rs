use indexmap::IndexMap;
use tempfile::{TempDir, tempdir};

use super::*;
use crate::{
    identity::{OperationIdentity, RequestId, ThreadId},
    storage::drafts::{DraftId, DraftRevision},
    workspace::{
        InteractionError, InteractionIdentity, InteractionKind, InteractionResponse,
        PendingInteraction, PermissionScope, SendDraft, SendIntent, SendSettings, WorkspaceAction,
        WorkspaceEngine,
    },
};

struct Fixture {
    engine: WorkspaceEngine,
    transport: Transport,
    input: JsonlReader<ReadHalf<DuplexStream>>,
    server_output: WriteHalf<DuplexStream>,
    _checkout: TempDir,
}

impl Fixture {
    async fn setup() -> Self {
        let folder = tempdir().unwrap();
        let checkout = CheckoutIdentity::capture(folder.path()).unwrap();
        let (transport, input, output) = transport_for(128, 1, Some(checkout));
        let client = &transport.client;
        let (engine, _effects) = WorkspaceEngine::start(client.identity().clone());
        for (index, name) in [(10, "hidden-thread"), (20, "another-thread")] {
            let operation = OperationIdentity {
                connection: client.identity().clone(),
                request: RequestId(Uuid::from_u128(index)),
            };
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
                    thread: ThreadId(name.into()),
                })
                .await
                .unwrap();
        }
        Self {
            engine,
            transport,
            input: JsonlReader::new(input, MAX_FRAME_BYTES),
            server_output: output,
            _checkout: folder,
        }
    }

    async fn register(&self, id: RpcId, method: &str, extra: Value) -> Arc<PendingInteraction> {
        let mut params = json!({
            "threadId": "hidden-thread", "turnId": "turn-1", "itemId": "item-1"
        });
        params
            .as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        self.engine
            .receive_interaction(
                &self.transport.client,
                ServerEvent::Request {
                    id,
                    method: method.into(),
                    params,
                },
                DEADLINE,
            )
            .await
            .unwrap()
            .unwrap()
    }

    async fn respond(
        &mut self,
        identity: InteractionIdentity,
        response: InteractionResponse,
    ) -> Value {
        let (sent, reply) = time::timeout(DEADLINE, async {
            tokio::join!(
                self.engine.respond_interaction(
                    &self.transport.client,
                    identity,
                    response,
                    DEADLINE
                ),
                next_request(&mut self.input),
            )
        })
        .await
        .unwrap();
        sent.unwrap();
        reply
    }

    async fn resolved(&self, id: &RpcId, thread: &str) {
        self.engine
            .receive_interaction(
                &self.transport.client,
                ServerEvent::Notification {
                    method: "serverRequest/resolved".into(),
                    params: json!({ "threadId": thread, "requestId": id }),
                },
                DEADLINE,
            )
            .await
            .unwrap();
    }
}

#[tokio::test]
async fn hidden_question_keeps_ordered_answers_and_routes_numeric_and_string_ids_separately() {
    let mut fixture = Fixture::setup().await;
    let method = "item/tool/requestUserInput";
    let questions = json!({
        "isBlocking": false,
        "questions": [{"id":"first"}, {"id":"second"}],
    });
    let numeric = fixture
        .register(RpcId::Integer(7), method, questions.clone())
        .await;
    let string = fixture
        .register(RpcId::String("7".into()), method, questions.clone())
        .await;
    assert_eq!(numeric.kind, InteractionKind::Question);
    assert_eq!(numeric.identity.thread.0, "hidden-thread");
    assert_eq!(numeric.parameters["isBlocking"], false);
    fixture
        .resolved(&numeric.identity.request, "another-thread")
        .await;

    let answers = || {
        InteractionResponse::Answers(IndexMap::from([
            (
                "first".into(),
                vec!["second answer".into(), "first answer".into()],
            ),
            ("second".into(), vec!["free text".into()]),
        ]))
    };
    let reply = fixture.respond(numeric.identity.clone(), answers()).await;
    assert_eq!(
        reply,
        json!({
            "id": 7,
            "result": {"answers": {
                "first": {"answers": ["second answer", "first answer"]},
                "second": {"answers": ["free text"]},
            }},
        })
    );
    assert!(matches!(
        fixture
            .engine
            .respond_interaction(
                &fixture.transport.client,
                numeric.identity.clone(),
                answers(),
                DEADLINE,
            )
            .await,
        Err(InteractionError::Duplicate)
    ));
    fixture
        .resolved(&numeric.identity.request, "hidden-thread")
        .await;
    let replacement = fixture.register(RpcId::Integer(7), method, questions).await;
    assert_ne!(replacement.identity, numeric.identity);
    assert!(matches!(
        fixture
            .engine
            .respond_interaction(
                &fixture.transport.client,
                numeric.identity.clone(),
                answers(),
                DEADLINE,
            )
            .await,
        Err(InteractionError::Resolved)
    ));
    let reply = fixture.respond(string.identity.clone(), answers()).await;
    assert_eq!(reply["id"], "7");
}

#[tokio::test]
async fn decision_responses_use_the_offered_choice_and_permissions_are_a_subset() {
    let mut fixture = Fixture::setup().await;
    let command = fixture
        .register(
            RpcId::Integer(1),
            "item/commandExecution/requestApproval",
            json!({"availableDecisions":["decline", "cancel"]}),
        )
        .await;
    assert!(matches!(
        fixture
            .engine
            .respond_interaction(
                &fixture.transport.client,
                command.identity.clone(),
                InteractionResponse::Decision(json!("accept")),
                DEADLINE,
            )
            .await,
        Err(InteractionError::InvalidAnswer)
    ));
    let reply = fixture
        .respond(
            command.identity.clone(),
            InteractionResponse::Decision(json!("decline")),
        )
        .await;
    assert_eq!(reply["result"], json!({"decision":"decline"}));

    let file = fixture
        .register(
            RpcId::Integer(2),
            "item/fileChange/requestApproval",
            json!({}),
        )
        .await;
    let reply = fixture
        .respond(
            file.identity.clone(),
            InteractionResponse::Decision(json!("acceptForSession")),
        )
        .await;
    assert_eq!(reply["result"], json!({"decision":"acceptForSession"}));

    let profile = json!({"network":{"enabled":true}});
    let permission = fixture
        .register(
            RpcId::Integer(3),
            "item/permissions/requestApproval",
            json!({"permissions": profile}),
        )
        .await;
    let expanded = json!({"network": {"enabled": true}, "fileSystem": {"write": ["/"]}});
    let granted = |profile: Value| InteractionResponse::Permissions {
        granted: profile.as_object().unwrap().clone(),
        scope: PermissionScope::Turn,
    };
    assert!(matches!(
        fixture
            .engine
            .respond_interaction(
                &fixture.transport.client,
                permission.identity.clone(),
                granted(expanded),
                DEADLINE,
            )
            .await,
        Err(InteractionError::InvalidAnswer)
    ));
    let reply = fixture
        .respond(permission.identity.clone(), granted(profile.clone()))
        .await;
    assert_eq!(
        reply["result"],
        json!({"permissions": profile, "scope":"turn"})
    );
}

#[tokio::test]
async fn unsupported_requests_receive_protocol_safe_replies_and_retired_requests_cannot_respond() {
    let mut fixture = Fixture::setup().await;
    let client = &fixture.transport.client;
    for (method, expected) in [
        (
            "different/request",
            json!({"code": -32601, "message": "Unsupported by this client"}),
        ),
        (
            "mcpServer/elicitation/request",
            json!({"action":"decline","content":null,"_meta":null}),
        ),
        ("execCommandApproval", json!({"decision":"abort"})),
    ] {
        let request = ServerEvent::Request {
            id: RpcId::String(method.into()),
            method: method.into(),
            params: Value::Null,
        };
        let (routed, wire) = time::timeout(DEADLINE, async {
            tokio::join!(
                fixture
                    .engine
                    .receive_interaction(client, request, DEADLINE),
                next_request(&mut fixture.input)
            )
        })
        .await
        .unwrap();
        assert!(routed.unwrap().is_none());
        assert_eq!(wire["id"], method);
        assert_eq!(wire.get("error").unwrap_or(&wire["result"]), &expected);
    }

    let pending = fixture
        .register(
            RpcId::Integer(1),
            "item/commandExecution/requestApproval",
            json!({}),
        )
        .await;
    let expected = client.identity().clone();
    let mut replacement = expected.clone();
    replacement.generation = ConnectionGeneration(2);
    fixture
        .engine
        .apply(WorkspaceAction::ReplaceConnection {
            expected,
            replacement,
        })
        .await
        .unwrap();
    assert!(matches!(
        fixture
            .engine
            .respond_interaction(
                client,
                pending.identity.clone(),
                InteractionResponse::Decision(json!("accept")),
                DEADLINE,
            )
            .await,
        Err(InteractionError::Retired)
    ));
}

#[tokio::test]
async fn server_resolution_cancels_a_queued_approval_before_any_reply_bytes() {
    let mut fixture = Fixture::setup().await;
    let pending = fixture
        .register(
            RpcId::Integer(9),
            "item/commandExecution/requestApproval",
            json!({}),
        )
        .await;
    let client = &fixture.transport.client;
    let engine = &fixture.engine;
    let (holding, hold_started) = oneshot::channel();
    let (reply, held, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            async {
                while client.shared.state.lock().unwrap().entries.len() != 1
                    || client.outbox.capacity() != MAX_PENDING_REQUESTS
                {
                    tokio::task::yield_now().await;
                }
                holding.send(()).unwrap();
                engine
                    .respond_interaction(
                        client,
                        pending.identity.clone(),
                        InteractionResponse::Decision(json!("accept")),
                        DEADLINE,
                    )
                    .await
            },
            client.request("fixture/hold", json!({"bytes":"x".repeat(4096)}), DEADLINE),
            async {
                hold_started.await.unwrap();
                while client.outbox.capacity() == MAX_PENDING_REQUESTS
                    || client.shared.state.lock().unwrap().entries.len() != 1
                {
                    tokio::task::yield_now().await;
                }
                engine
                    .receive_interaction(
                        client,
                        ServerEvent::Notification {
                            method: "serverRequest/resolved".into(),
                            params: json!({ "threadId": "hidden-thread", "requestId": 9 }),
                        },
                        DEADLINE,
                    )
                    .await
                    .unwrap();
                let request = next_request(&mut fixture.input).await;
                assert_eq!(request["method"], "fixture/hold");
                respond(
                    &mut fixture.server_output,
                    request["id"].clone(),
                    Value::Null,
                )
                .await;
            },
        )
    })
    .await
    .unwrap();
    assert!(
        matches!(
            reply,
            Err(InteractionError::Send(RequestError::Stopped(
                Delivery::Unsent
            )))
        ),
        "{reply:?}"
    );
    held.unwrap();
    let (next, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            client.request("fixture/next", Value::Null, DEADLINE),
            async {
                let request = next_request(&mut fixture.input).await;
                assert_eq!(request["method"], "fixture/next");
                respond(
                    &mut fixture.server_output,
                    request["id"].clone(),
                    Value::Null,
                )
                .await;
            }
        )
    })
    .await
    .unwrap();
    next.unwrap();
}
