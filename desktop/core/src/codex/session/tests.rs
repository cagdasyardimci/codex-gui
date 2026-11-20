use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream, ReadHalf, WriteHalf, duplex, split};
use uuid::Uuid;

use super::*;
use crate::{
    checkout::CheckoutIdentity,
    identity::{CheckoutSessionId, ConnectionGeneration, WorkspaceIdentity},
};

const DEADLINE: Duration = Duration::from_secs(5);

fn transport(
    capacity: usize,
    generation: u64,
) -> (Transport, ReadHalf<DuplexStream>, WriteHalf<DuplexStream>) {
    transport_for(capacity, generation, None)
}

fn transport_for(
    capacity: usize,
    generation: u64,
    checkout: Option<CheckoutIdentity>,
) -> (Transport, ReadHalf<DuplexStream>, WriteHalf<DuplexStream>) {
    let (app, server) = duplex(capacity);
    let (app_in, app_out) = split(app);
    let (server_in, server_out) = split(server);
    let (events, inbox) = mpsc::channel(MAX_QUEUED_EVENTS);
    let identity = ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::from_u128(1)),
            checkout,
        },
        generation: ConnectionGeneration(generation),
    };
    let transport = Transport::launch(
        identity,
        JsonlReader::new(app_in, MAX_FRAME_BYTES),
        app_out,
        events,
        inbox,
    );
    (transport, server_in, server_out)
}

async fn next_request(reader: &mut JsonlReader<ReadHalf<DuplexStream>>) -> Value {
    let frame = reader.next_frame().await.unwrap().unwrap();
    serde_json::from_slice(&frame).unwrap()
}

async fn respond(server: &mut WriteHalf<DuplexStream>, id: Value, payload: Value) {
    server
        .write_all(&encode_frame(&json!({"id": id, "result": payload})).unwrap())
        .await
        .unwrap();
}

#[tokio::test]
async fn routes_out_of_order_replies_without_consuming_server_requests() {
    let (mut transport, server_in, mut server_out) = transport(4096, 1);
    let client = transport.client.clone();
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);

    let (first, second, ()) = time::timeout(DEADLINE, async {
        tokio::join!(
            client.request("first", Value::Null, DEADLINE),
            client.request("second", Value::Null, DEADLINE),
            async {
                let first = next_request(&mut server).await;
                let second = next_request(&mut server).await;
                let id_as_string = first["id"].as_i64().unwrap().to_string();
                let event = encode_frame(&json!({"id": id_as_string, "method": "ask"})).unwrap();
                server_out.write_all(&event).await.unwrap();
                respond(&mut server_out, json!(id_as_string), json!("wrong ID type")).await;
                respond(
                    &mut server_out,
                    second["id"].clone(),
                    second["method"].clone(),
                )
                .await;
                respond(
                    &mut server_out,
                    first["id"].clone(),
                    first["method"].clone(),
                )
                .await;
                assert_eq!(
                    transport.inbox.recv().await.unwrap(),
                    ServerEvent::Request {
                        id: RpcId::String(id_as_string),
                        method: "ask".into(),
                        params: Value::Null,
                    }
                );
            }
        )
    })
    .await
    .unwrap();
    assert_eq!(first.unwrap(), json!("first"));
    assert_eq!(second.unwrap(), json!("second"));
}

#[tokio::test]
async fn expiry_while_queued_never_writes_that_frame() {
    let (transport, mut server_in, mut server_out) = transport(8, 1);
    let client = transport.client.clone();
    let first_client = client.clone();
    let first =
        tokio::spawn(async move { first_client.request("first", Value::Null, DEADLINE).await });

    time::timeout(DEADLINE, async {
        let mut byte = [0];
        server_in.read_exact(&mut byte).await.unwrap();
        let timed_out = client
            .request("expired", Value::Null, Duration::from_millis(60))
            .await;
        assert!(
            matches!(timed_out, Err(RequestError::Timeout(Delivery::Unsent))),
            "{timed_out:?}"
        );

        let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);
        let tail = server.next_frame().await.unwrap().unwrap();
        let request: Value = serde_json::from_slice(&[byte.as_slice(), &tail].concat()).unwrap();
        respond(&mut server_out, request["id"].clone(), json!("accepted")).await;
        assert_eq!(first.await.unwrap().unwrap(), json!("accepted"));

        let (result, ()) = tokio::join!(client.request("after", Value::Null, DEADLINE), async {
            let request = next_request(&mut server).await;
            assert_eq!(request["method"], "after");
            respond(&mut server_out, request["id"].clone(), Value::Null).await;
        });
        assert_eq!(result.unwrap(), Value::Null);
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn partial_write_is_uncertain_and_closes_the_incomplete_stream() {
    let (transport, mut server_in, _server_out) = transport(8, 1);
    let client = transport.client.clone();

    time::timeout(DEADLINE, async {
        let (result, _) = tokio::join!(
            client.request("partially-written", Value::Null, Duration::from_millis(100)),
            async {
                let mut byte = [0];
                server_in.read_exact(&mut byte).await.unwrap();
                assert_eq!(byte, [b'{']);
            }
        );
        assert!(
            matches!(result, Err(RequestError::Timeout(Delivery::PossiblySent))),
            "{result:?}"
        );

        let mut remainder = Vec::new();
        server_in.read_to_end(&mut remainder).await.unwrap();
        assert!(!remainder.contains(&b'\n'));
        assert!(matches!(
            client.request("new", Value::Null, DEADLINE).await,
            Err(RequestError::Disconnected(Delivery::Unsent))
        ));
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn late_reply_from_retired_generation_cannot_complete_replacement_request() {
    let (old, old_in, mut old_out) = transport(1024, 1);
    let (new, new_in, mut new_out) = transport(1024, 2);
    let mut old_server = JsonlReader::new(old_in, MAX_FRAME_BYTES);
    let mut new_server = JsonlReader::new(new_in, MAX_FRAME_BYTES);
    let old_client = old.client.clone();

    time::timeout(DEADLINE, async {
        let old_request =
            tokio::spawn(
                async move { old_client.request("original", Value::Null, DEADLINE).await },
            );
        let read_old = next_request(&mut old_server).await;
        old.retire();
        assert!(matches!(
            old_request.await.unwrap(),
            Err(RequestError::Disconnected(Delivery::PossiblySent))
        ));

        let (result, ()) = tokio::join!(
            new.client.request("replacement", Value::Null, DEADLINE),
            async {
                let read_new = next_request(&mut new_server).await;
                assert_eq!(read_old["id"], read_new["id"]);
                let late = encode_frame(&json!({"id": read_old["id"], "result": "old"})).unwrap();
                let _ = old_out.write_all(&late).await;
                respond(&mut new_out, read_new["id"].clone(), json!("new")).await;
            }
        );
        assert_eq!(result.unwrap(), json!("new"));
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn timeout_after_a_complete_frame_ignores_the_late_reply_and_keeps_the_stream() {
    let (transport, server_in, mut server_out) = transport(1024, 1);
    let client = transport.client.clone();
    let mut server = JsonlReader::new(server_in, MAX_FRAME_BYTES);

    time::timeout(DEADLINE, async {
        let (timed_out, expired) = tokio::join!(
            client.request("expired", Value::Null, Duration::from_millis(100)),
            next_request(&mut server),
        );
        assert!(matches!(
            timed_out,
            Err(RequestError::Timeout(Delivery::PossiblySent))
        ));
        respond(&mut server_out, expired["id"].clone(), json!("late")).await;

        let (result, ()) = tokio::join!(client.request("after", Value::Null, DEADLINE), async {
            let request = next_request(&mut server).await;
            assert_ne!(request["id"], expired["id"]);
            respond(&mut server_out, request["id"].clone(), json!("current")).await;
        });
        assert_eq!(result.unwrap(), json!("current"));
    })
    .await
    .unwrap();
}

mod browse;
mod interactions;
mod prepare;
mod submission;
