use std::{
    collections::HashMap,
    io,
    sync::{Arc, Mutex},
    time::Duration,
};

use serde_json::{Value, json};
use thiserror::Error;
use tokio::{
    io::{AsyncRead, AsyncWrite},
    sync::{OwnedSemaphorePermit, Semaphore, mpsc, oneshot},
    task::JoinHandle,
    time::{self, Instant},
};

use crate::identity::ConnectionIdentity;

use super::protocol::{MAX_FRAME_BYTES, encode_frame};
use super::{
    AppServerExit, AppServerProcess, CliCompatibility, ClientInfo, CodexExecutable,
    CompatibilityError, InitializeError, JsonlReader, RpcError, RpcId, ServerEvent, ServerMessage,
    StderrTail, VersionProbeError, initialize, read_message,
};

mod writer;
pub use writer::Delivery;
use writer::{Outbound, WriteTicket};

const MAX_PENDING_REQUESTS: usize = 16;
const MAX_QUEUED_EVENTS: usize = 64;
const MAX_STDERR_BYTES: usize = 8 * 1024;

#[derive(Debug, Error)]
pub enum ConnectError {
    #[error(transparent)]
    Probe(#[from] VersionProbeError),
    #[error(transparent)]
    Compatibility(#[from] CompatibilityError),
    #[error("could not launch Codex app-server: {0}")]
    Spawn(#[from] io::Error),
    #[error(transparent)]
    Initialize(#[from] InitializeError),
}

#[derive(Debug, Error)]
pub enum RequestError {
    #[error("app-server request timed out ({0:?})")]
    Timeout(Delivery),
    #[error("app-server connection retired ({0:?})")]
    Disconnected(Delivery),
    #[error("could not encode app-server request: {0}")]
    Encode(#[from] io::Error),
    #[error(transparent)]
    Remote(#[from] RpcError),
    #[error("no more app-server request IDs are available")]
    IdExhausted,
}

pub struct AppServerConnection {
    transport: Transport,
    process: AppServerProcess,
    diagnostics: StderrTail,
    stderr_task: JoinHandle<()>,
    compatibility: CliCompatibility,
    initialization: Value,
}

impl AppServerConnection {
    pub async fn connect(
        executable: &CodexExecutable,
        connection: ConnectionIdentity,
        info: ClientInfo<'_>,
        startup_timeout: Duration,
    ) -> Result<Self, ConnectError> {
        let deadline = Instant::now() + startup_timeout;
        let report = executable.probe_version(startup_timeout).await?;
        let compatibility = CliCompatibility::from_version_output(&report)?;
        if Instant::now() >= deadline {
            return Err(InitializeError::Timeout.into());
        }
        let mut process = AppServerProcess::spawn(executable, connection.clone())?;
        let initialization_timeout = deadline.saturating_duration_since(Instant::now());
        let pipes = process
            .take_stdio()
            .expect("new app-server has all stdio pipes");
        let mut input = JsonlReader::new(pipes.stdout, MAX_FRAME_BYTES);
        let mut output = pipes.stdin;
        let mut stderr = pipes.stderr;
        let (events, inbox) = mpsc::channel(MAX_QUEUED_EVENTS);
        let diagnostics = StderrTail::new(MAX_STDERR_BYTES);
        let initialization = {
            let handshake = initialize(
                &mut input,
                &mut output,
                info,
                initialization_timeout,
                |event| events.try_send(event).is_ok(),
            );
            tokio::pin!(handshake);
            tokio::select! {
                result = &mut handshake => result,
                _ = diagnostics.drain(&mut stderr) => handshake.await,
            }
        }?;
        let drain = diagnostics.clone();
        let stderr_task = tokio::spawn(async move {
            let _ = drain.drain(stderr).await;
        });

        Ok(Self {
            transport: Transport::launch(connection, input, output, events, inbox),
            process,
            diagnostics,
            stderr_task,
            compatibility,
            initialization,
        })
    }

    pub fn client(&self) -> AppServerClient {
        self.transport.client.clone()
    }

    pub fn initialization(&self) -> &Value {
        &self.initialization
    }

    pub fn compatibility(&self) -> &CliCompatibility {
        &self.compatibility
    }

    pub fn diagnostics(&self) -> &StderrTail {
        &self.diagnostics
    }

    pub async fn next_event(&mut self) -> Option<ServerEvent> {
        self.transport.inbox.recv().await
    }

    pub async fn disconnect(mut self) -> io::Result<AppServerExit> {
        self.transport.retire();
        self.process.terminate().await
    }
}

impl Drop for AppServerConnection {
    fn drop(&mut self) {
        self.stderr_task.abort();
    }
}

#[derive(Clone)]
pub struct AppServerClient {
    shared: Arc<Shared>,
    outbox: mpsc::Sender<Outbound>,
}

impl AppServerClient {
    pub fn identity(&self) -> &ConnectionIdentity {
        &self.shared.connection
    }

    pub async fn request(
        &self,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<Value, RequestError> {
        let deadline = Instant::now() + timeout;
        let permit = time::timeout_at(deadline, self.shared.slots.clone().acquire_owned())
            .await
            .map_err(|_| RequestError::Timeout(Delivery::Unsent))?
            .map_err(|_| RequestError::Disconnected(Delivery::Unsent))?;
        let (request, reply) = self.shared.register(deadline, permit)?;
        let bytes = encode_frame(&json!({"id": request.id, "method": method, "params": params}))?;
        let frame = Outbound {
            bytes,
            deadline,
            ticket: request.ticket.clone(),
        };

        match time::timeout_at(deadline, self.outbox.send(frame)).await {
            Ok(Ok(())) => {}
            Ok(Err(_)) => return Err(RequestError::Disconnected(request.ticket.cancel())),
            Err(_) => return Err(RequestError::Timeout(request.ticket.cancel())),
        }
        match time::timeout_at(deadline, reply).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(RequestError::Disconnected(request.ticket.cancel())),
            Err(_) => Err(RequestError::Timeout(request.ticket.cancel())),
        }
    }
}

struct Transport {
    client: AppServerClient,
    inbox: mpsc::Receiver<ServerEvent>,
    work: JoinHandle<()>,
}

impl Transport {
    fn launch<R, W>(
        connection: ConnectionIdentity,
        input: JsonlReader<R>,
        output: W,
        events: mpsc::Sender<ServerEvent>,
        inbox: mpsc::Receiver<ServerEvent>,
    ) -> Self
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let shared = Arc::new(Shared {
            connection,
            slots: Arc::new(Semaphore::new(MAX_PENDING_REQUESTS)),
            state: Mutex::new(PendingRequests {
                next_id: 1,
                ..PendingRequests::default()
            }),
        });
        let (outbox, frames) = mpsc::channel(MAX_PENDING_REQUESTS);
        let owner = shared.clone();
        let work = tokio::spawn(async move {
            tokio::select! {
                _ = read_events(input, events, &owner) => {}
                _ = writer::run(output, frames, &owner) => {}
            }
            owner.retire();
        });

        Self {
            client: AppServerClient { shared, outbox },
            inbox,
            work,
        }
    }

    fn retire(&self) {
        self.client.shared.retire();
        self.work.abort();
    }
}

impl Drop for Transport {
    fn drop(&mut self) {
        self.retire();
    }
}

async fn read_events<R: AsyncRead + Unpin>(
    mut input: JsonlReader<R>,
    events: mpsc::Sender<ServerEvent>,
    shared: &Shared,
) {
    while let Ok(Some(message)) = read_message(&mut input).await {
        match message {
            ServerMessage::Reply {
                id: RpcId::Integer(id),
                result,
            } => shared.reply(id, result),
            ServerMessage::Reply { .. } => {}
            ServerMessage::Event(event) => {
                if events.try_send(event).is_err() {
                    // A saturated consumer must reconnect rather than lose server requests.
                    break;
                }
            }
        }
    }
}

struct Shared {
    connection: ConnectionIdentity,
    slots: Arc<Semaphore>,
    state: Mutex<PendingRequests>,
}

#[derive(Default)]
struct PendingRequests {
    retired: bool,
    next_id: i64,
    entries: HashMap<i64, PendingReply>,
}

struct PendingReply {
    sender: oneshot::Sender<Result<Value, RequestError>>,
    ticket: Arc<WriteTicket>,
    deadline: Instant,
}

struct RequestGuard {
    shared: Arc<Shared>,
    id: i64,
    ticket: Arc<WriteTicket>,
    _permit: OwnedSemaphorePermit,
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        let mut state = self
            .shared
            .state
            .lock()
            .expect("pending request lock poisoned");
        if state.entries.remove(&self.id).is_some() {
            self.ticket.cancel();
        }
    }
}

impl Shared {
    fn register(
        self: &Arc<Self>,
        deadline: Instant,
        permit: OwnedSemaphorePermit,
    ) -> Result<(RequestGuard, oneshot::Receiver<Result<Value, RequestError>>), RequestError> {
        let mut state = self.state.lock().expect("pending request lock poisoned");
        if state.retired {
            return Err(RequestError::Disconnected(Delivery::Unsent));
        }
        let id = state.next_id;
        state.next_id = id.checked_add(1).ok_or(RequestError::IdExhausted)?;
        let ticket = Arc::new(WriteTicket::default());
        let (sender, receiver) = oneshot::channel();
        state.entries.insert(
            id,
            PendingReply {
                sender,
                ticket: ticket.clone(),
                deadline,
            },
        );
        Ok((
            RequestGuard {
                shared: self.clone(),
                id,
                ticket,
                _permit: permit,
            },
            receiver,
        ))
    }

    fn reply(&self, id: i64, result: Result<Value, RpcError>) {
        let mut state = self.state.lock().expect("pending request lock poisoned");
        if state.entries.get(&id).is_some_and(|reply| {
            Instant::now() < reply.deadline && reply.ticket.can_receive_reply()
        }) {
            let entry = state
                .entries
                .remove(&id)
                .expect("entry was found under the lock");
            let _ = entry.sender.send(result.map_err(RequestError::Remote));
        }
    }

    fn retire(&self) {
        let mut state = self.state.lock().expect("pending request lock poisoned");
        state.retired = true;
        self.slots.close();
        let pending = std::mem::take(&mut state.entries);
        drop(state);

        for entry in pending.into_values() {
            let delivery = entry.ticket.cancel();
            let error = if Instant::now() >= entry.deadline {
                RequestError::Timeout(delivery)
            } else {
                RequestError::Disconnected(delivery)
            };
            let _ = entry.sender.send(Err(error));
        }
    }
}

#[cfg(test)]
mod tests;
