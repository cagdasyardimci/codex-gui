use std::{io, time::Duration};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;
use tokio::{
    io::{AsyncRead, AsyncWrite, AsyncWriteExt},
    time,
};

use super::{JsonlReadError, JsonlReader};

pub(crate) const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;
const INITIALIZE_ID: RpcId = RpcId::Integer(0);

#[derive(Clone, Debug, Eq, Hash, PartialEq, Serialize)]
#[serde(untagged)]
pub enum RpcId {
    Integer(i64),
    String(String),
}

#[derive(Debug, Deserialize, Error, PartialEq, Serialize)]
#[error("app-server RPC error {code}: {message}")]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, PartialEq)]
pub enum ServerEvent {
    Notification {
        method: String,
        params: Value,
    },
    Request {
        id: RpcId,
        method: String,
        params: Value,
    },
}

#[derive(Debug, PartialEq)]
pub enum ServerMessage {
    Reply {
        id: RpcId,
        result: Result<Value, RpcError>,
    },
    Event(ServerEvent),
}

#[derive(Debug, Error)]
pub enum ProtocolReadError {
    #[error(transparent)]
    Frame(#[from] JsonlReadError),
    #[error("invalid app-server JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("invalid app-server envelope: {0}")]
    Shape(&'static str),
}

pub async fn read_message<R: AsyncRead + Unpin>(
    reader: &mut JsonlReader<R>,
) -> Result<Option<ServerMessage>, ProtocolReadError> {
    reader
        .next_frame()
        .await?
        .as_deref()
        .map(decode)
        .transpose()
}

fn decode(frame: &[u8]) -> Result<ServerMessage, ProtocolReadError> {
    let Value::Object(mut fields) = serde_json::from_slice(frame)? else {
        return Err(ProtocolReadError::Shape("expected an object"));
    };
    let id = fields.remove("id").map(decode_id).transpose()?;
    let result = fields.remove("result");
    let error = fields.remove("error");

    if let Some(method) = fields.remove("method") {
        let Value::String(method) = method else {
            return Err(ProtocolReadError::Shape("method must be a string"));
        };
        if method.is_empty() || result.is_some() || error.is_some() {
            return Err(ProtocolReadError::Shape("invalid method envelope"));
        }
        let params = fields.remove("params").unwrap_or(Value::Null);
        let event = match id {
            Some(id) => ServerEvent::Request { id, method, params },
            None => ServerEvent::Notification { method, params },
        };
        return Ok(ServerMessage::Event(event));
    }

    let id = id.ok_or(ProtocolReadError::Shape("reply is missing an ID"))?;
    let result = match (result, error) {
        (Some(result), None) => Ok(result),
        (None, Some(error)) => Err(serde_json::from_value(error)?),
        _ => {
            return Err(ProtocolReadError::Shape(
                "reply needs exactly one result or error",
            ));
        }
    };
    Ok(ServerMessage::Reply { id, result })
}

fn decode_id(id: Value) -> Result<RpcId, ProtocolReadError> {
    match id {
        Value::String(id) => Ok(RpcId::String(id)),
        Value::Number(id) => id
            .as_i64()
            .map(RpcId::Integer)
            .ok_or(ProtocolReadError::Shape(
                "ID must be a signed integer or a string",
            )),
        _ => Err(ProtocolReadError::Shape(
            "ID must be a signed integer or a string",
        )),
    }
}

#[derive(Serialize)]
pub struct ClientInfo<'a> {
    pub name: &'a str,
    pub title: &'a str,
    pub version: &'a str,
}

#[derive(Debug, Error)]
pub enum InitializeError {
    #[error("app-server initialization timed out")]
    Timeout,
    #[error("app-server closed during initialization")]
    Disconnected,
    #[error("app-server replied to an unknown request during initialization")]
    UnexpectedReply,
    #[error("app-server initialization event was not accepted")]
    EventRejected,
    #[error(transparent)]
    Protocol(#[from] ProtocolReadError),
    #[error(transparent)]
    Remote(#[from] RpcError),
    #[error("could not write app-server initialization message: {0}")]
    Write(#[from] io::Error),
}

/// Exchanges the handshake on owned pipes. Retire the transport if initialization fails.
pub async fn initialize<R: AsyncRead + Unpin, W: AsyncWrite + Unpin>(
    input: &mut JsonlReader<R>,
    output: &mut W,
    client: ClientInfo<'_>,
    deadline: Duration,
    mut on_event: impl FnMut(ServerEvent) -> bool,
) -> Result<Value, InitializeError> {
    time::timeout(deadline, async {
        let frame = encode_frame(&json!({
            "id": INITIALIZE_ID,
            "method": "initialize",
            "params": {
                "clientInfo": client,
                "capabilities": { "experimentalApi": true, "requestAttestation": false }
            }
        }))?;
        output.write_all(&frame).await?;
        output.flush().await?;

        let result = loop {
            match read_message(input).await? {
                Some(ServerMessage::Reply { id, result }) if id == INITIALIZE_ID => break result?,
                Some(ServerMessage::Reply { .. }) => return Err(InitializeError::UnexpectedReply),
                Some(ServerMessage::Event(event)) => {
                    if !on_event(event) {
                        return Err(InitializeError::EventRejected);
                    }
                }
                None => return Err(InitializeError::Disconnected),
            }
        };

        output
            .write_all(&encode_frame(&json!({"method": "initialized"}))?)
            .await?;
        output.flush().await?;
        Ok(result)
    })
    .await
    .map_err(|_| InitializeError::Timeout)?
}

pub(crate) fn encode_frame(message: &Value) -> io::Result<Vec<u8>> {
    let mut frame = BoundedFrame(Vec::new());
    serde_json::to_writer(&mut frame, message).map_err(io::Error::from)?;
    frame.0.push(b'\n');
    Ok(frame.0)
}

struct BoundedFrame(Vec<u8>);

impl io::Write for BoundedFrame {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAX_FRAME_BYTES - self.0.len() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "app-server output frame exceeds its byte limit",
            ));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests;
