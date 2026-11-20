use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use indexmap::IndexMap;
use serde::Serialize;
use serde_json::{Map, Value, json};
use thiserror::Error;
use tokio::sync::watch;

use super::{NavigationRow, NavigationTarget, WorkspaceEngine};

use crate::{
    codex::{AppServerClient, RequestError, RpcError, RpcId, ServerEvent},
    identity::{ConnectionIdentity, ThreadId, TurnId},
};

const MAX_PENDING: usize = 128;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InteractionKind {
    Command,
    FileChange,
    Permission,
    Question,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InteractionIdentity {
    pub connection: ConnectionIdentity,
    pub thread: ThreadId,
    pub turn: TurnId,
    pub item: String,
    pub request: RpcId,
    sequence: u64,
}

#[derive(Debug)]
pub struct PendingInteraction {
    pub identity: InteractionIdentity,
    pub kind: InteractionKind,
    pub parameters: Value,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionScope {
    Turn,
    Session,
}

pub enum InteractionResponse {
    Decision(Value),
    Permissions {
        granted: Map<String, Value>,
        scope: PermissionScope,
    },
    Answers(IndexMap<String, Vec<String>>),
}

#[derive(Debug, Error)]
pub enum InteractionError {
    #[error("interaction belongs to a retired connection")]
    Retired,
    #[error("interaction does not identify an owned chat, turn, and item")]
    Unowned,
    #[error("interaction was already registered or answered")]
    Duplicate,
    #[error("interaction is no longer pending")]
    Resolved,
    #[error("interaction queue reached its limit")]
    AtCapacity,
    #[error("response does not match the server request")]
    InvalidAnswer,
    #[error(transparent)]
    Send(#[from] RequestError),
    #[error(transparent)]
    Worker(#[from] tokio::task::JoinError),
}

#[derive(Clone)]
pub(super) struct InteractionRouter {
    state: Arc<Mutex<State>>,
}

struct State {
    owner: ConnectionIdentity,
    generation_retired: watch::Sender<bool>,
    pending: HashMap<RpcId, Slot>,
    sequence: u64,
}

struct Slot {
    request: Arc<PendingInteraction>,
    retired: watch::Sender<bool>,
    reply_reserved: bool,
}

impl InteractionRouter {
    pub(super) fn new(owner: ConnectionIdentity) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                owner,
                generation_retired: watch::Sender::new(false),
                pending: HashMap::new(),
                sequence: 0,
            })),
        }
    }

    pub(super) fn replace_connection(&self, owner: ConnectionIdentity) {
        let mut state = self.state.lock().expect("interaction router lock poisoned");
        state.generation_retired.send_replace(true);
        for (_, slot) in state.pending.drain() {
            slot.retired.send_replace(true);
        }
        state.owner = owner;
        state.generation_retired = watch::Sender::new(false);
        state.sequence = 0;
    }

    async fn receive(
        &self,
        client: &AppServerClient,
        event: ServerEvent,
        timeout: Duration,
        rows: &[NavigationRow],
    ) -> Result<Option<Arc<PendingInteraction>>, InteractionError> {
        match event {
            ServerEvent::Request { id, method, params } => {
                let kind = match method.as_str() {
                    "item/commandExecution/requestApproval" => InteractionKind::Command,
                    "item/fileChange/requestApproval" => InteractionKind::FileChange,
                    "item/permissions/requestApproval" => InteractionKind::Permission,
                    "item/tool/requestUserInput" => InteractionKind::Question,
                    _ => {
                        let retired = {
                            let state =
                                self.state.lock().expect("interaction router lock poisoned");
                            let retired = state.generation_scope(client.identity())?;
                            if state.pending.contains_key(&id) {
                                return Err(InteractionError::Duplicate);
                            }
                            retired
                        };
                        client
                            .respond_scoped(&id, unsupported_reply(&method), timeout, retired)
                            .await?;
                        return Ok(None);
                    }
                };
                let mut state = self.state.lock().expect("interaction router lock poisoned");
                Ok(Some(state.register(
                    client.identity(),
                    id,
                    kind,
                    params,
                    rows,
                )?))
            }
            ServerEvent::Notification { method, params } if method == "serverRequest/resolved" => {
                let mut state = self.state.lock().expect("interaction router lock poisoned");
                state.resolve(client.identity(), &params)?;
                Ok(None)
            }
            ServerEvent::Notification { .. } => Ok(None),
        }
    }

    async fn respond(
        &self,
        client: &AppServerClient,
        identity: InteractionIdentity,
        response: InteractionResponse,
        timeout: Duration,
    ) -> Result<(), InteractionError> {
        let router = self.clone();
        let client = client.clone();
        tokio::spawn(async move {
            let (payload, retired) = router
                .state
                .lock()
                .expect("interaction router lock poisoned")
                .reserve_reply(client.identity(), &identity, response)?;
            let result = client
                .respond_scoped(&identity.request, Ok(payload), timeout, retired)
                .await;
            if result.as_ref().is_err_and(RequestError::is_unsent) {
                let mut state = router
                    .state
                    .lock()
                    .expect("interaction router lock poisoned");
                if let Some(slot) = state.pending.get_mut(&identity.request)
                    && slot.request.identity == identity
                {
                    slot.reply_reserved = false;
                }
            }
            Ok(result?)
        })
        .await?
    }
}

impl State {
    fn generation_scope(
        &self,
        owner: &ConnectionIdentity,
    ) -> Result<watch::Receiver<bool>, InteractionError> {
        if &self.owner != owner {
            return Err(InteractionError::Retired);
        }
        Ok(self.generation_retired.subscribe())
    }

    fn register(
        &mut self,
        owner: &ConnectionIdentity,
        request: RpcId,
        kind: InteractionKind,
        parameters: Value,
        rows: &[NavigationRow],
    ) -> Result<Arc<PendingInteraction>, InteractionError> {
        self.generation_scope(owner)?;
        if self.pending.contains_key(&request) {
            return Err(InteractionError::Duplicate);
        }
        if self.pending.len() == MAX_PENDING {
            return Err(InteractionError::AtCapacity);
        }
        let thread = ThreadId(required_string(&parameters["threadId"])?);
        if !rows
            .iter()
            .any(|row| matches!(&row.target, NavigationTarget::Thread(id) if id == &thread))
        {
            return Err(InteractionError::Unowned);
        }
        let identity = InteractionIdentity {
            connection: owner.clone(),
            thread,
            turn: TurnId(required_string(&parameters["turnId"])?),
            item: required_string(&parameters["itemId"])?,
            request: request.clone(),
            sequence: self.sequence,
        };
        self.sequence = self
            .sequence
            .checked_add(1)
            .ok_or(InteractionError::AtCapacity)?;
        let interaction = Arc::new(PendingInteraction {
            identity,
            kind,
            parameters,
        });
        self.pending.insert(
            request,
            Slot {
                request: interaction.clone(),
                retired: watch::Sender::new(false),
                reply_reserved: false,
            },
        );
        Ok(interaction)
    }

    fn resolve(
        &mut self,
        owner: &ConnectionIdentity,
        params: &Value,
    ) -> Result<(), InteractionError> {
        self.generation_scope(owner)?;
        let request = match &params["requestId"] {
            Value::String(id) => RpcId::String(id.clone()),
            id => RpcId::Integer(id.as_i64().ok_or(InteractionError::Unowned)?),
        };
        if self
            .pending
            .get(&request)
            .is_some_and(|slot| params["threadId"] == slot.request.identity.thread.0)
        {
            self.pending
                .remove(&request)
                .expect("matched pending request")
                .retired
                .send_replace(true);
        }
        Ok(())
    }

    fn reserve_reply(
        &mut self,
        owner: &ConnectionIdentity,
        identity: &InteractionIdentity,
        response: InteractionResponse,
    ) -> Result<(Value, watch::Receiver<bool>), InteractionError> {
        self.generation_scope(owner)?;
        if owner != &identity.connection {
            return Err(InteractionError::Retired);
        }
        let slot = self
            .pending
            .get_mut(&identity.request)
            .filter(|slot| &slot.request.identity == identity)
            .ok_or(InteractionError::Resolved)?;
        if slot.reply_reserved {
            return Err(InteractionError::Duplicate);
        }
        let payload = validated_reply(&slot.request, response)?;
        slot.reply_reserved = true;
        Ok((payload, slot.retired.subscribe()))
    }
}

impl WorkspaceEngine {
    pub async fn receive_interaction(
        &self,
        client: &AppServerClient,
        event: ServerEvent,
        timeout: Duration,
    ) -> Result<Option<Arc<PendingInteraction>>, InteractionError> {
        self.interactions
            .receive(client, event, timeout, &self.snapshot().rows)
            .await
    }

    pub async fn respond_interaction(
        &self,
        client: &AppServerClient,
        identity: InteractionIdentity,
        response: InteractionResponse,
        timeout: Duration,
    ) -> Result<(), InteractionError> {
        self.interactions
            .respond(client, identity, response, timeout)
            .await
    }
}

fn required_string(value: &Value) -> Result<String, InteractionError> {
    value
        .as_str()
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or(InteractionError::Unowned)
}

fn validated_reply(
    request: &PendingInteraction,
    response: InteractionResponse,
) -> Result<Value, InteractionError> {
    let parameters = &request.parameters;
    match (request.kind, response) {
        (
            InteractionKind::Command | InteractionKind::FileChange,
            InteractionResponse::Decision(decision),
        ) if allowed_decision(request.kind, parameters, &decision) => {
            Ok(json!({ "decision": decision }))
        }
        (InteractionKind::Permission, InteractionResponse::Permissions { granted, scope }) => {
            let granted = Value::Object(granted);
            if !is_subset(&granted, &parameters["permissions"]) {
                return Err(InteractionError::InvalidAnswer);
            }
            Ok(json!({ "permissions": granted, "scope": scope }))
        }
        (InteractionKind::Question, InteractionResponse::Answers(answers)) => {
            let questions = parameters["questions"]
                .as_array()
                .ok_or(InteractionError::InvalidAnswer)?;
            if answers
                .keys()
                .any(|id| !questions.iter().any(|question| question["id"] == *id))
            {
                return Err(InteractionError::InvalidAnswer);
            }
            let answers: Map<_, _> = answers
                .into_iter()
                .map(|(id, answers)| (id, json!({ "answers": answers })))
                .collect();
            Ok(json!({ "answers": answers }))
        }
        _ => Err(InteractionError::InvalidAnswer),
    }
}

fn allowed_decision(kind: InteractionKind, parameters: &Value, decision: &Value) -> bool {
    if let Some(available) = parameters["availableDecisions"].as_array() {
        return available.contains(decision);
    }
    if matches!(
        decision.as_str(),
        Some("accept" | "acceptForSession" | "decline" | "cancel")
    ) {
        return true;
    }
    if kind != InteractionKind::Command {
        return false;
    }
    if let Some(execpolicy) = parameters["proposedExecpolicyAmendment"].as_array()
        && decision
            == &json!({ "acceptWithExecpolicyAmendment": { "execpolicy_amendment": execpolicy } })
    {
        return true;
    }
    parameters["proposedNetworkPolicyAmendments"].as_array().is_some_and(|values| {
        values.iter().any(|value| decision == &json!({ "applyNetworkPolicyAmendment": { "network_policy_amendment": value } }))
    })
}

fn is_subset(granted: &Value, requested: &Value) -> bool {
    match (granted, requested) {
        (Value::Object(granted), Value::Object(requested)) => granted.iter().all(|(key, value)| {
            requested
                .get(key)
                .is_some_and(|requested| is_subset(value, requested))
        }),
        (Value::Array(granted), Value::Array(requested)) => {
            granted.iter().all(|value| requested.contains(value))
        }
        _ => granted == requested,
    }
}

fn unsupported_reply(method: &str) -> Result<Value, RpcError> {
    match method {
        "mcpServer/elicitation/request" => {
            Ok(json!({ "action": "decline", "content": null, "_meta": null }))
        }
        "applyPatchApproval" | "execCommandApproval" => Ok(json!({ "decision": "abort" })),
        _ => Err(RpcError {
            code: -32601,
            message: "Unsupported by this client".into(),
            data: None,
        }),
    }
}
