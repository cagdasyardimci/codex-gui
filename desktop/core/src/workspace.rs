use std::{collections::HashMap, sync::Arc};

use indexmap::IndexMap;
use thiserror::Error;
use tokio::sync::{mpsc, oneshot, watch};

use crate::{
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId},
    storage::drafts::DraftId,
};

const ACTION_CAPACITY: usize = 32;
const EFFECT_CAPACITY: usize = 16;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NavigationTarget {
    Preparing(RequestId),
    Thread(ThreadId),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NavigationRow {
    pub draft: DraftId,
    pub target: NavigationTarget,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorkspaceSnapshot {
    pub connection: ConnectionIdentity,
    pub revision: u64,
    pub rows: Vec<NavigationRow>,
}

pub enum WorkspaceAction {
    AdmitFirstMessage {
        operation: OperationIdentity,
        draft: DraftId,
    },
    ThreadPrepared {
        operation: OperationIdentity,
        thread: ThreadId,
    },
    PreparationFailed {
        operation: OperationIdentity,
    },
    ReplaceConnection {
        expected: ConnectionIdentity,
        replacement: ConnectionIdentity,
    },
}

#[derive(Debug, Eq, PartialEq)]
pub struct PrepareThread {
    pub operation: OperationIdentity,
    pub draft: DraftId,
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum WorkspaceError {
    #[error("the checkout state loop is closed")]
    Closed,
    #[error("the operation belongs to a retired checkout session or connection")]
    Retired,
    #[error("select a checkout before starting a chat")]
    MissingCheckout,
    #[error("the draft or request already has a navigation owner")]
    AlreadyAdmitted,
    #[error("the preparation is no longer pending")]
    MissingPreparation,
    #[error("the prepared thread is empty or already belongs to a navigation owner")]
    InvalidThread,
    #[error("the workspace effect queue is full")]
    EffectQueueFull,
    #[error("the workspace effect queue is closed")]
    EffectQueueClosed,
}

#[derive(Clone)]
pub struct WorkspaceEngine {
    actions: mpsc::Sender<Message>,
    snapshots: watch::Receiver<Arc<WorkspaceSnapshot>>,
}

struct Message {
    action: WorkspaceAction,
    completion: oneshot::Sender<Result<u64, WorkspaceError>>,
}

impl WorkspaceEngine {
    pub fn start(connection: ConnectionIdentity) -> (Self, mpsc::Receiver<PrepareThread>) {
        let mut state = State::new(connection);
        let (actions, mut incoming) = mpsc::channel::<Message>(ACTION_CAPACITY);
        let (effects, pending_effects) = mpsc::channel(EFFECT_CAPACITY);
        let (publish, snapshots) = watch::channel(state.snapshot());
        tokio::spawn(async move {
            while let Some(message) = incoming.recv().await {
                let outcome = state.apply(message.action, &effects).map(|()| {
                    state.revision = state
                        .revision
                        .checked_add(1)
                        .expect("workspace revision exhausted");
                    publish.send_replace(state.snapshot());
                    state.revision
                });
                let _ = message.completion.send(outcome);
            }
        });
        (Self { actions, snapshots }, pending_effects)
    }

    pub fn snapshot(&self) -> Arc<WorkspaceSnapshot> {
        self.snapshots.borrow().clone()
    }

    pub async fn apply(&self, action: WorkspaceAction) -> Result<u64, WorkspaceError> {
        let (completion, received) = oneshot::channel();
        self.actions
            .send(Message { action, completion })
            .await
            .map_err(|_| WorkspaceError::Closed)?;
        received.await.map_err(|_| WorkspaceError::Closed)?
    }
}

struct State {
    connection: ConnectionIdentity,
    revision: u64,
    rows: IndexMap<DraftId, NavigationTarget>,
    pending: HashMap<RequestId, DraftId>,
    threads: HashMap<ThreadId, DraftId>,
}

impl State {
    fn new(connection: ConnectionIdentity) -> Self {
        Self {
            connection,
            revision: 0,
            rows: IndexMap::new(),
            pending: HashMap::new(),
            threads: HashMap::new(),
        }
    }

    fn snapshot(&self) -> Arc<WorkspaceSnapshot> {
        Arc::new(WorkspaceSnapshot {
            connection: self.connection.clone(),
            revision: self.revision,
            rows: self
                .rows
                .iter()
                .map(|(draft, target)| NavigationRow {
                    draft: *draft,
                    target: target.clone(),
                })
                .collect(),
        })
    }

    fn apply(
        &mut self,
        action: WorkspaceAction,
        effects: &mpsc::Sender<PrepareThread>,
    ) -> Result<(), WorkspaceError> {
        match action {
            WorkspaceAction::AdmitFirstMessage { operation, draft } => {
                self.admit(operation, draft, effects)
            }
            WorkspaceAction::ThreadPrepared { operation, thread } => {
                self.bind_thread(&operation, thread)
            }
            WorkspaceAction::PreparationFailed { operation } => {
                let draft = self.pending_draft(&operation)?;
                self.pending.remove(&operation.request);
                self.rows.shift_remove(&draft);
                Ok(())
            }
            WorkspaceAction::ReplaceConnection {
                expected,
                replacement,
            } => self.replace_connection(expected, replacement),
        }
    }

    fn admit(
        &mut self,
        operation: OperationIdentity,
        draft: DraftId,
        effects: &mpsc::Sender<PrepareThread>,
    ) -> Result<(), WorkspaceError> {
        self.validate_owner(&operation)?;
        if self.connection.workspace.checkout.is_none() {
            return Err(WorkspaceError::MissingCheckout);
        }
        if self.pending.contains_key(&operation.request) || self.rows.contains_key(&draft) {
            return Err(WorkspaceError::AlreadyAdmitted);
        }
        let slot = effects.try_reserve().map_err(|error| match error {
            mpsc::error::TrySendError::Full(()) => WorkspaceError::EffectQueueFull,
            mpsc::error::TrySendError::Closed(()) => WorkspaceError::EffectQueueClosed,
        })?;
        self.pending.insert(operation.request, draft);
        self.rows
            .insert(draft, NavigationTarget::Preparing(operation.request));
        slot.send(PrepareThread { operation, draft });
        Ok(())
    }

    fn bind_thread(
        &mut self,
        operation: &OperationIdentity,
        thread: ThreadId,
    ) -> Result<(), WorkspaceError> {
        let draft = self.pending_draft(operation)?;
        if thread.0.is_empty() || self.threads.contains_key(&thread) {
            return Err(WorkspaceError::InvalidThread);
        }
        self.pending.remove(&operation.request);
        self.threads.insert(thread.clone(), draft);
        self.rows.insert(draft, NavigationTarget::Thread(thread));
        Ok(())
    }

    fn pending_draft(&self, operation: &OperationIdentity) -> Result<DraftId, WorkspaceError> {
        self.validate_owner(operation)?;
        self.pending
            .get(&operation.request)
            .copied()
            .ok_or(WorkspaceError::MissingPreparation)
    }

    fn validate_owner(&self, operation: &OperationIdentity) -> Result<(), WorkspaceError> {
        if operation.connection != self.connection {
            return Err(WorkspaceError::Retired);
        }
        Ok(())
    }

    fn replace_connection(
        &mut self,
        expected: ConnectionIdentity,
        replacement: ConnectionIdentity,
    ) -> Result<(), WorkspaceError> {
        if self.connection != expected
            || expected.workspace != replacement.workspace
            || replacement.generation.0 <= expected.generation.0
        {
            return Err(WorkspaceError::Retired);
        }
        self.rows
            .retain(|_, target| matches!(target, NavigationTarget::Thread(_)));
        self.pending.clear();
        self.connection = replacement;
        Ok(())
    }
}

#[cfg(test)]
mod tests;
