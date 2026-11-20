use std::{collections::HashMap, time::Duration};

use indexmap::IndexSet;
use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::watch;

use super::{WorkspaceAction, WorkspaceEngine, WorkspaceError};
use crate::{
    codex::{AppServerClient, RequestError, ServerEvent},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
};

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ExecutionTarget {
    pub thread: ThreadId,
    pub turn: TurnId,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct CommandExecution {
    pub target: ExecutionTarget,
    pub item: String,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ExecutionSnapshot {
    pub active_turns: Vec<ExecutionTarget>,
    pub unresolved_commands: Vec<CommandExecution>,
}

pub struct ExecutionObservation {
    pub(super) owner: ConnectionIdentity,
    pub(super) target: ExecutionTarget,
    kind: ObservationKind,
}

enum ObservationKind {
    TurnStarted,
    TurnEnded,
    CommandStarted(String),
    CommandEnded(String),
}

#[derive(Default)]
pub(super) struct ExecutionState {
    active: IndexSet<ExecutionTarget>,
    commands: IndexSet<CommandExecution>,
    interrupts: HashMap<ExecutionTarget, InterruptClaim>,
}

struct InterruptClaim {
    request: RequestId,
    stopped: watch::Sender<bool>,
}

#[derive(Debug, Error)]
pub enum InterruptError {
    #[error(transparent)]
    Workspace(#[from] WorkspaceError),
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Worker(#[from] tokio::task::JoinError),
}

impl ExecutionState {
    pub(super) fn snapshot(&self) -> ExecutionSnapshot {
        ExecutionSnapshot {
            active_turns: self.active.iter().cloned().collect(),
            unresolved_commands: self.commands.iter().cloned().collect(),
        }
    }

    pub(super) fn observe(&mut self, event: ExecutionObservation) {
        let target = event.target;
        match event.kind {
            ObservationKind::TurnStarted => {
                self.active.insert(target);
            }
            ObservationKind::TurnEnded => {
                self.active.shift_remove(&target);
                if let Some(claim) = self.interrupts.remove(&target) {
                    claim.stopped.send_replace(true);
                }
            }
            ObservationKind::CommandStarted(item) => {
                self.commands.insert(CommandExecution { target, item });
            }
            ObservationKind::CommandEnded(item) => {
                self.commands
                    .shift_remove(&CommandExecution { target, item });
            }
        }
    }

    pub(super) fn reserve_interrupt(
        &mut self,
        request: RequestId,
        target: ExecutionTarget,
        stopped: watch::Sender<bool>,
    ) -> Result<(), WorkspaceError> {
        if !self.active.contains(&target) {
            return Err(WorkspaceError::InactiveTurn);
        }
        if self.interrupts.contains_key(&target) {
            return Err(WorkspaceError::InterruptPending);
        }
        self.interrupts
            .insert(target, InterruptClaim { request, stopped });
        Ok(())
    }

    pub(super) fn release_interrupt(&mut self, request: RequestId, target: &ExecutionTarget) {
        if self
            .interrupts
            .get(target)
            .is_some_and(|claim| claim.request == request)
        {
            self.interrupts.remove(target);
        }
    }

    pub(super) fn retire_connection(&mut self) {
        self.active.clear();
        for (_, claim) in self.interrupts.drain() {
            claim.stopped.send_replace(true);
        }
    }
}

impl WorkspaceEngine {
    pub async fn observe_execution_event(
        &self,
        owner: &ConnectionIdentity,
        event: &ServerEvent,
    ) -> Result<Option<u64>, WorkspaceError> {
        let Some(observation) = execution_observation(owner, event) else {
            return Ok(None);
        };
        self.apply(WorkspaceAction::ObserveExecution(observation))
            .await
            .map(Some)
    }

    pub async fn interrupt(
        &self,
        operation: OperationIdentity,
        target: ExecutionTarget,
        client: &AppServerClient,
        timeout: Duration,
    ) -> Result<(), InterruptError> {
        if client.identity() != &operation.connection {
            return Err(WorkspaceError::Retired.into());
        }
        let checkout = operation
            .connection
            .workspace
            .checkout
            .clone()
            .ok_or(WorkspaceError::MissingCheckout)?;
        let engine = self.clone();
        let client = client.clone();
        tokio::spawn(async move {
            let (stop, stopped) = watch::channel(false);
            engine
                .apply(WorkspaceAction::ReserveInterrupt {
                    operation: operation.clone(),
                    target: target.clone(),
                    stopped: stop,
                })
                .await?;
            let result = client
                .request_scoped(
                    "turn/interrupt",
                    json!({"threadId": target.thread.0, "turnId": target.turn.0}),
                    timeout,
                    checkout,
                    stopped,
                )
                .await;
            if result
                .as_ref()
                .is_err_and(|error| error.is_unsent() || matches!(error, RequestError::Remote(_)))
            {
                let _ = engine
                    .apply(WorkspaceAction::ReleaseInterrupt { operation, target })
                    .await;
            }
            result?;
            Ok(())
        })
        .await?
    }
}

fn execution_observation(
    owner: &ConnectionIdentity,
    event: &ServerEvent,
) -> Option<ExecutionObservation> {
    let ServerEvent::Notification { method, params } = event else {
        return None;
    };
    let thread = ThreadId(identifier(&params["threadId"])?);
    let (turn, kind) = match method.as_str() {
        "turn/started" => (
            identifier(&params["turn"]["id"])?,
            ObservationKind::TurnStarted,
        ),
        "turn/completed"
            if matches!(
                params["turn"]["status"].as_str(),
                Some("completed" | "failed" | "interrupted")
            ) =>
        {
            (
                identifier(&params["turn"]["id"])?,
                ObservationKind::TurnEnded,
            )
        }
        "item/started" | "item/completed" if params["item"]["type"] == "commandExecution" => {
            let item = &params["item"];
            let id = identifier(&item["id"])?;
            let kind = match (method.as_str(), item["status"].as_str()) {
                ("item/started", Some("inProgress")) => ObservationKind::CommandStarted(id),
                ("item/completed", Some("completed" | "failed" | "declined")) => {
                    ObservationKind::CommandEnded(id)
                }
                _ => return None,
            };
            (identifier(&params["turnId"])?, kind)
        }
        _ => return None,
    };
    Some(ExecutionObservation {
        owner: owner.clone(),
        target: ExecutionTarget {
            thread,
            turn: TurnId(turn),
        },
        kind,
    })
}

fn identifier(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}
