use std::{path::PathBuf, sync::Arc, time::Duration};

use serde::Deserialize;
use serde_json::json;
use thiserror::Error;
use tokio::sync::watch;
use uuid::Uuid;

use super::{
    NavigationTarget, PrepareThread, SendIntent, WorkspaceAction, WorkspaceEngine, WorkspaceError,
};
use crate::{
    checkout::CheckoutError,
    codex::{AppServerClient, RequestError},
    identity::ThreadId,
    storage::attachments::{AttachmentError, AttachmentStore},
    worktree::{WorktreeError, WorktreeManager},
};

pub struct WorktreeThreadBinding {
    pub manager: WorktreeManager,
    pub record: Uuid,
    pub resume: Option<ThreadId>,
}

#[derive(Debug, Error)]
pub enum PrepareError {
    #[error(transparent)]
    Workspace(#[from] WorkspaceError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Draft(#[from] AttachmentError),
    #[error(transparent)]
    Worktree(#[from] WorktreeError),
    #[error(transparent)]
    Worker(#[from] tokio::task::JoinError),
    #[error("checkout path cannot be represented in the Codex protocol")]
    NonUnicodeCheckout,
    #[error("invalid response from thread/start: {0}")]
    Response(#[from] serde_json::Error),
}

#[derive(Deserialize)]
struct StartedThread {
    thread: ThreadLocation,
    cwd: PathBuf,
}

#[derive(Deserialize)]
struct ThreadLocation {
    id: ThreadId,
    cwd: PathBuf,
}

pub struct PreparedThread {
    pub(super) intent: Arc<SendIntent>,
    pub(super) thread: ThreadId,
    pub(super) stopped: watch::Receiver<bool>,
}

impl PreparedThread {
    pub fn thread(&self) -> &ThreadId {
        &self.thread
    }
}

impl WorkspaceEngine {
    pub async fn prepare_thread(
        &self,
        effect: PrepareThread,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<PreparedThread, PrepareError> {
        self.prepare_thread_with_worktree(effect, client, store, timeout, None)
            .await
    }

    pub async fn prepare_thread_with_worktree(
        &self,
        effect: PrepareThread,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
        binding: Option<WorktreeThreadBinding>,
    ) -> Result<PreparedThread, PrepareError> {
        // The admitted effect owns cleanup and publication even if the
        // caller stops waiting. Retirement is an explicit workspace action.
        let engine = self.clone();
        let client = client.clone();
        let store = store.clone();
        tokio::spawn(async move {
            let intent = effect.intent;
            let operation = intent.operation.clone();
            let outcome = engine
                .prepare_and_bind(intent.clone(), &client, store, timeout, binding)
                .await;
            if outcome.is_err() {
                let _ = engine
                    .apply(WorkspaceAction::PreparationFailed { operation })
                    .await;
            }
            outcome.map(|thread| PreparedThread {
                intent,
                thread,
                stopped: effect.stopped,
            })
        })
        .await?
    }

    async fn prepare_and_bind(
        &self,
        intent: Arc<SendIntent>,
        client: &AppServerClient,
        store: AttachmentStore,
        timeout: Duration,
        binding: Option<WorktreeThreadBinding>,
    ) -> Result<ThreadId, PrepareError> {
        self.check_pending(&intent)?;
        let operation = intent.operation.clone();
        if client.identity() != &operation.connection {
            return Err(WorkspaceError::Retired.into());
        }
        let checkout = operation
            .connection
            .workspace
            .checkout
            .as_ref()
            .ok_or(WorkspaceError::MissingCheckout)?;
        checkout.revalidate()?;
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(PrepareError::NonUnicodeCheckout)?;
        // Recover a thread that was recorded before draft promotion completed.
        let resume = binding.as_ref().and_then(|binding| binding.resume.as_ref());
        let (method, params) = match resume {
            Some(thread) => (
                "thread/resume",
                json!({ "threadId": thread.0, "cwd": cwd, "excludeTurns": true }),
            ),
            None => ("thread/start", json!({ "cwd": cwd })),
        };
        let reply = client.request(method, params, timeout).await?;
        let started: StartedThread = serde_json::from_value(reply)?;
        checkout.validate_reported(&started.cwd)?;
        checkout.validate_reported(&started.thread.cwd)?;
        let thread = started.thread.id;
        if resume.is_some_and(|expected| expected != &thread) {
            return Err(WorkspaceError::InvalidThread.into());
        }

        // Keep retirement and competing bindings out of the durable
        // commit-to-publication interval. The actor still accepts new drafts.
        let _commit = self.preparation_commit.lock().await;
        self.check_pending(&intent)?;
        if thread.0.is_empty() || self.snapshot().rows.iter().any(
            |row| matches!(&row.target, NavigationTarget::Thread(existing) if existing == &thread),
        ) {
            return Err(WorkspaceError::InvalidThread.into());
        }
        if let Some(binding) = binding {
            binding
                .manager
                .bind(binding.record, &thread.0, checkout.canonical_path())
                .await?;
        }
        let checkout = checkout.clone();
        let thread = tokio::task::spawn_blocking(move || {
            checkout.revalidate()?;
            let draft = &intent.draft;
            store.bind_thread_draft(
                &thread,
                draft.id,
                draft.revision,
                &draft.text,
                &draft.context,
                &draft.attachments,
            )?;
            Ok::<_, PrepareError>(thread)
        })
        .await??;
        self.dispatch(WorkspaceAction::ThreadPrepared {
            operation,
            thread: thread.clone(),
        })
        .await?;
        Ok(thread)
    }

    fn check_pending(&self, intent: &SendIntent) -> Result<(), WorkspaceError> {
        let snapshot = self.snapshot();
        if snapshot.connection != intent.operation.connection {
            return Err(WorkspaceError::Retired);
        }
        if !snapshot.rows.iter().any(|row| {
            row.draft == intent.draft.id
                && row.target == NavigationTarget::Preparing(intent.operation.request)
        }) {
            return Err(WorkspaceError::MissingPreparation);
        }
        Ok(())
    }
}
