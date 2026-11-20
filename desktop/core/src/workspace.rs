use std::{collections::HashMap, sync::Arc};

use indexmap::IndexMap;
use thiserror::Error;
use tokio::sync::{Mutex, mpsc, oneshot, watch};

use crate::{
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId},
    storage::drafts::DraftId,
};

mod interactions;
mod prepare;
mod send;
mod submission;

pub use crate::storage::attachments::SubmissionAcknowledgement;
use interactions::InteractionRouter;
pub use interactions::{
    InteractionError, InteractionIdentity, InteractionKind, InteractionResponse,
    PendingInteraction, PermissionScope,
};
pub use prepare::{PrepareError, PreparedThread};
pub use send::{SendDraft, SendIntent, SendSettings};
pub use submission::{SubmissionError, SubmissionReply};

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
    AdmitFirstMessage(Arc<SendIntent>),
    ThreadPrepared {
        operation: OperationIdentity,
        thread: ThreadId,
    },
    PreparationFailed {
        operation: OperationIdentity,
    },
    StopSubmission {
        operation: OperationIdentity,
    },
    SubmissionFinished {
        operation: OperationIdentity,
    },
    ReplaceConnection {
        expected: ConnectionIdentity,
        replacement: ConnectionIdentity,
    },
}

pub struct PrepareThread {
    intent: Arc<SendIntent>,
    stopped: watch::Receiver<bool>,
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum WorkspaceError {
    #[error("the checkout state loop is closed")]
    Closed,
    #[error("the operation belongs to a retired checkout session or connection")]
    Retired,
    #[error("select a checkout before starting a chat")]
    MissingCheckout,
    #[error("the draft has no content to send")]
    EmptyDraft,
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
    preparation_commit: Arc<Mutex<()>>,
    interactions: InteractionRouter,
}

struct Message {
    action: WorkspaceAction,
    completion: oneshot::Sender<Result<u64, WorkspaceError>>,
}

impl WorkspaceEngine {
    pub fn start(connection: ConnectionIdentity) -> (Self, mpsc::Receiver<PrepareThread>) {
        let interactions = InteractionRouter::new(connection.clone());
        let mut state = State::new(connection, interactions.clone());
        let (actions, mut incoming) = mpsc::channel::<Message>(ACTION_CAPACITY);
        let (effects, pending_effects) = mpsc::channel(EFFECT_CAPACITY);
        let (publish, snapshots) = watch::channel(state.snapshot());
        tokio::spawn(async move {
            while let Some(message) = incoming.recv().await {
                let outcome = state.apply(message.action, &effects).map(|prepared| {
                    state.revision = state
                        .revision
                        .checked_add(1)
                        .expect("workspace revision exhausted");
                    publish.send_replace(state.snapshot());
                    if let Some((slot, effect)) = prepared {
                        slot.send(effect);
                    }
                    state.revision
                });
                let _ = message.completion.send(outcome);
            }
        });
        (
            Self {
                actions,
                snapshots,
                preparation_commit: Arc::new(Mutex::new(())),
                interactions,
            },
            pending_effects,
        )
    }

    pub fn snapshot(&self) -> Arc<WorkspaceSnapshot> {
        self.snapshots.borrow().clone()
    }

    pub async fn apply(&self, action: WorkspaceAction) -> Result<u64, WorkspaceError> {
        if matches!(action, WorkspaceAction::AdmitFirstMessage(_)) {
            return self.dispatch(action).await;
        }
        let _commit = self.preparation_commit.lock().await;
        self.dispatch(action).await
    }

    async fn dispatch(&self, action: WorkspaceAction) -> Result<u64, WorkspaceError> {
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
    pending: HashMap<RequestId, Arc<SendIntent>>,
    threads: HashMap<ThreadId, DraftId>,
    submissions: HashMap<RequestId, watch::Sender<bool>>,
    interactions: InteractionRouter,
}

type ReservedPreparation = (mpsc::OwnedPermit<PrepareThread>, PrepareThread);

impl State {
    fn new(connection: ConnectionIdentity, interactions: InteractionRouter) -> Self {
        Self {
            connection,
            revision: 0,
            rows: IndexMap::new(),
            pending: HashMap::new(),
            threads: HashMap::new(),
            submissions: HashMap::new(),
            interactions,
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
    ) -> Result<Option<ReservedPreparation>, WorkspaceError> {
        match action {
            WorkspaceAction::AdmitFirstMessage(intent) => self.admit(intent, effects).map(Some),
            WorkspaceAction::ThreadPrepared { operation, thread } => {
                self.bind_thread(&operation, thread).map(|()| None)
            }
            WorkspaceAction::PreparationFailed { operation } => {
                let draft = self.pending_draft(&operation)?;
                self.pending.remove(&operation.request);
                self.rows.shift_remove(&draft);
                self.submissions.remove(&operation.request);
                Ok(None)
            }
            WorkspaceAction::StopSubmission { operation } => {
                self.validate_owner(&operation)?;
                let stopped = self
                    .submissions
                    .remove(&operation.request)
                    .ok_or(WorkspaceError::MissingPreparation)?;
                stopped.send_replace(true);
                if let Some(intent) = self.pending.remove(&operation.request) {
                    self.rows.shift_remove(&intent.draft.id);
                }
                Ok(None)
            }
            WorkspaceAction::SubmissionFinished { operation } => {
                self.validate_owner(&operation)?;
                self.submissions.remove(&operation.request);
                Ok(None)
            }
            WorkspaceAction::ReplaceConnection {
                expected,
                replacement,
            } => self
                .replace_connection(expected, replacement)
                .map(|()| None),
        }
    }

    fn admit(
        &mut self,
        intent: Arc<SendIntent>,
        effects: &mpsc::Sender<PrepareThread>,
    ) -> Result<ReservedPreparation, WorkspaceError> {
        self.validate_owner(&intent.operation)?;
        if self.connection.workspace.checkout.is_none() {
            return Err(WorkspaceError::MissingCheckout);
        }
        if !intent.draft.has_content() {
            return Err(WorkspaceError::EmptyDraft);
        }
        let request = intent.operation.request;
        let draft = intent.draft.id;
        if self.submissions.contains_key(&request) || self.rows.contains_key(&draft) {
            return Err(WorkspaceError::AlreadyAdmitted);
        }
        let slot = effects
            .clone()
            .try_reserve_owned()
            .map_err(|error| match error {
                mpsc::error::TrySendError::Full(_) => WorkspaceError::EffectQueueFull,
                mpsc::error::TrySendError::Closed(_) => WorkspaceError::EffectQueueClosed,
            })?;
        self.pending.insert(request, intent.clone());
        self.rows
            .insert(draft, NavigationTarget::Preparing(request));
        let (stop, stopped) = watch::channel(false);
        self.submissions.insert(request, stop);
        Ok((slot, PrepareThread { intent, stopped }))
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
            .map(|intent| intent.draft.id)
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
        for (_, stopped) in self.submissions.drain() {
            stopped.send_replace(true);
        }
        self.interactions.replace_connection(replacement.clone());
        self.connection = replacement;
        Ok(())
    }
}

#[cfg(test)]
mod tests;
