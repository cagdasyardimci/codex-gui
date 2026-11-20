use std::{path::PathBuf, sync::Arc, time::Duration};

use serde::Deserialize;
use serde_json::json;
use thiserror::Error;

use super::{
    NavigationTarget, PrepareThread, SendIntent, WorkspaceAction, WorkspaceEngine, WorkspaceError,
};
use crate::{
    checkout::CheckoutError,
    codex::{AppServerClient, RequestError},
    identity::ThreadId,
    storage::attachments::{AttachmentError, AttachmentStore},
};

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

impl WorkspaceEngine {
    pub async fn prepare_thread(
        &self,
        effect: PrepareThread,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<ThreadId, PrepareError> {
        // The admitted effect owns cleanup and publication even if the
        // caller stops waiting. Retirement is an explicit workspace action.
        let engine = self.clone();
        let client = client.clone();
        let store = store.clone();
        tokio::spawn(async move {
            let intent = effect.intent;
            let operation = intent.operation.clone();
            let outcome = engine
                .prepare_and_bind(intent, &client, store, timeout)
                .await;
            if outcome.is_err() {
                let _ = engine
                    .apply(WorkspaceAction::PreparationFailed { operation })
                    .await;
            }
            outcome
        })
        .await?
    }

    async fn prepare_and_bind(
        &self,
        intent: Arc<SendIntent>,
        client: &AppServerClient,
        store: AttachmentStore,
        timeout: Duration,
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
        let reply = client
            .request("thread/start", json!({ "cwd": cwd }), timeout)
            .await?;
        let started: StartedThread = serde_json::from_value(reply)?;
        checkout.validate_reported(&started.cwd)?;
        checkout.validate_reported(&started.thread.cwd)?;
        let thread = started.thread.id;

        // Keep retirement and competing bindings out of the durable
        // commit-to-publication interval. The actor still accepts new drafts.
        let _commit = self.preparation_commit.lock().await;
        self.check_pending(&intent)?;
        if thread.0.is_empty() || self.snapshot().rows.iter().any(
            |row| matches!(&row.target, NavigationTarget::Thread(existing) if existing == &thread),
        ) {
            return Err(WorkspaceError::InvalidThread.into());
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
