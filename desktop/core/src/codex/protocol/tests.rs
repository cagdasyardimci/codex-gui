use super::*;
use tokio::{
    io::{AsyncWriteExt, duplex, split},
    sync::mpsc,
};

#[test]
fn keeps_numeric_and_string_server_request_ids_distinct() {
    for (frame, expected_id) in [
        (
            br#"{"id":13,"method":"approval"}"#.as_slice(),
            RpcId::Integer(13),
        ),
        (
            br#"{"id":"13","method":"approval"}"#.as_slice(),
            RpcId::String("13".into()),
        ),
    ] {
        assert_eq!(
            decode(frame).unwrap(),
            ServerMessage::Event(ServerEvent::Request {
                id: expected_id,
                method: "approval".into(),
                params: Value::Null,
            })
        );
    }
    assert!(matches!(
        decode(br#"{"id":13.0,"method":"approval"}"#),
        Err(ProtocolReadError::Shape(_))
    ));
}

#[test]
fn preserves_a_null_result_and_the_error_data() {
    assert_eq!(
        decode(br#"{"id":42,"result":null}"#).unwrap(),
        ServerMessage::Reply {
            id: RpcId::Integer(42),
            result: Ok(Value::Null)
        }
    );
    assert_eq!(
        decode(
            br#"{"id":"42","error":{"code":-32001,"message":"retired","data":{"generation":2}}}"#
        )
        .unwrap(),
        ServerMessage::Reply {
            id: RpcId::String("42".into()),
            result: Err(RpcError {
                code: -32001,
                message: "retired".into(),
                data: Some(json!({"generation": 2})),
            }),
        }
    );
    assert!(matches!(
        decode(br#"{"id":42,"result":null,"error":null}"#),
        Err(ProtocolReadError::Shape(_))
    ));
}

#[tokio::test]
async fn routes_early_events_before_acknowledging_initialization() {
    let (application, server) = duplex(4096);
    let (app_in, mut app_out) = split(application);
    let (server_in, mut server_out) = split(server);
    let mut app_input = JsonlReader::new(app_in, MAX_FRAME_BYTES);
    let mut server_input = JsonlReader::new(server_in, MAX_FRAME_BYTES);
    let (send, mut received_events) = mpsc::channel(2);
    let client = ClientInfo {
        name: "codex_gui_tauri",
        title: "Codex GUI",
        version: "0.1.0",
    };

    time::timeout(Duration::from_secs(5), async {
        let (result, ()) = tokio::join!(
            initialize(&mut app_input, &mut app_out, client, Duration::from_secs(4), |event| {
                send.try_send(event).is_ok()
            }),
            async {
                let request = server_input.next_frame().await.unwrap().unwrap();
                let request: Value = serde_json::from_slice(&request).unwrap();
                assert_eq!(request, json!({
                    "id": 0,
                    "method": "initialize",
                    "params": {
                        "clientInfo": { "name": "codex_gui_tauri", "title": "Codex GUI", "version": "0.1.0" },
                        "capabilities": { "experimentalApi": true, "requestAttestation": false }
                    }
                }));
                server_out.write_all(b"{\"method\":\"early/update\",\"params\":{\"value\":1}}\n{\"id\":\"early\",\"method\":\"early/request\"}\n").await.unwrap();
                assert_eq!(received_events.recv().await.unwrap(), ServerEvent::Notification {
                    method: "early/update".into(), params: json!({"value": 1}),
                });
                assert_eq!(received_events.recv().await.unwrap(), ServerEvent::Request {
                    id: RpcId::String("early".into()), method: "early/request".into(), params: Value::Null,
                });
                server_out.write_all(b"{\"id\":0,\"result\":{\"userAgent\":\"fixture\"}}\n").await.unwrap();
                let initialized = server_input.next_frame().await.unwrap().unwrap();
                let initialized: Value = serde_json::from_slice(&initialized).unwrap();
                assert_eq!(initialized, json!({"method":"initialized"}));
            }
        );
        assert_eq!(result.unwrap(), json!({"userAgent": "fixture"}));
    }).await.unwrap();
}
