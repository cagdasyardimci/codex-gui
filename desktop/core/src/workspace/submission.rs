use std::{sync::Arc, time::Duration};

use serde::Deserialize;
use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::watch;
use uuid::Uuid;

use super::{
    ExecutionTarget, PreparedThread, SendIntent, SubmissionAcknowledgement, WorkspaceAction,
    WorkspaceEngine, WorkspaceError,
};
use crate::{
    checkout::CheckoutError,
    codex::{AppServerClient, Delivery, QueuedSubmission, RequestError, ServerEvent},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{
        AttachmentStore, JournalEntry, JournalError, JournalOutcome, JournalPhase, SubmissionWrite,
    },
};

#[derive(Debug, Error)]
pub enum SubmissionError {
    #[error(transparent)]
    Workspace(#[from] WorkspaceError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Journal(#[from] JournalError),
    #[error(transparent)]
    Worker(#[from] tokio::task::JoinError),
    #[error("a captured path cannot be represented in the Codex protocol")]
    NonUnicodePath,
}

#[derive(Debug)]
pub struct SubmissionReply {
    pub operation: OperationIdentity,
    pub thread: ThreadId,
    pub response: Result<Value, RequestError>,
    pub acknowledgement: SubmissionAcknowledgement,
}

enum SubmissionKind {
    Turn,
    Queue,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct QueueAddReply {
    queued_submission: QueuedSubmission,
}

impl WorkspaceEngine {
    pub async fn reserve_thread_submission(
        &self,
        intent: Arc<SendIntent>,
        thread: ThreadId,
    ) -> Result<PreparedThread, WorkspaceError> {
        self.reserve_submission(intent, thread, None).await
    }

    async fn reserve_submission(
        &self,
        intent: Arc<SendIntent>,
        thread: ThreadId,
        active_turn: Option<TurnId>,
    ) -> Result<PreparedThread, WorkspaceError> {
        if !intent.draft.has_content() {
            return Err(WorkspaceError::EmptyDraft);
        }
        let (stop, stopped) = watch::channel(false);
        self.apply(WorkspaceAction::ReserveThreadSubmission {
            operation: intent.operation.clone(),
            thread: thread.clone(),
            active_turn,
            stopped: stop,
        })
        .await?;
        Ok(PreparedThread {
            intent,
            thread,
            stopped,
        })
    }

    pub async fn submit_prepared(
        &self,
        prepared: PreparedThread,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<SubmissionReply, SubmissionError> {
        let engine = self.clone();
        let client = client.clone();
        let store = store.clone();
        tokio::spawn(async move {
            engine
                .finish_submission(prepared, SubmissionKind::Turn, &client, &store, timeout)
                .await
        })
        .await?
    }

    pub async fn enqueue_follow_up(
        &self,
        intent: Arc<SendIntent>,
        target: ExecutionTarget,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<SubmissionReply, SubmissionError> {
        let engine = self.clone();
        let client = client.clone();
        let store = store.clone();
        tokio::spawn(async move {
            let prepared = engine
                .reserve_submission(intent, target.thread, Some(target.turn))
                .await?;
            engine
                .finish_submission(prepared, SubmissionKind::Queue, &client, &store, timeout)
                .await
        })
        .await?
    }

    async fn finish_submission(
        &self,
        prepared: PreparedThread,
        kind: SubmissionKind,
        client: &AppServerClient,
        store: &AttachmentStore,
        timeout: Duration,
    ) -> Result<SubmissionReply, SubmissionError> {
        let operation = prepared.intent.operation.clone();
        let outcome = async {
            let (response, _write) = dispatch(&prepared, &kind, client, store, timeout).await?;
            let acknowledgement = match reply_outcome(&kind, operation.request, &response) {
                Some(outcome) => {
                    self.acknowledge(&operation, &prepared.thread, outcome, store)
                        .await?
                }
                None => SubmissionAcknowledgement::Unmatched,
            };
            Ok(SubmissionReply {
                operation: operation.clone(),
                thread: prepared.thread,
                response,
                acknowledgement,
            })
        }
        .await;
        let _ = self
            .apply(WorkspaceAction::SubmissionFinished { operation })
            .await;
        outcome
    }

    pub async fn observe_submission_event(
        &self,
        owner: &ConnectionIdentity,
        event: &ServerEvent,
        store: &AttachmentStore,
    ) -> Result<SubmissionAcknowledgement, SubmissionError> {
        let Some((request, thread, turn)) = message_evidence(event) else {
            return Ok(SubmissionAcknowledgement::Unmatched);
        };
        let operation = OperationIdentity {
            connection: owner.clone(),
            request,
        };
        self.acknowledge(&operation, &thread, JournalOutcome::Accepted(turn), store)
            .await
    }

    pub(super) async fn acknowledge(
        &self,
        operation: &OperationIdentity,
        thread: &ThreadId,
        outcome: JournalOutcome,
        store: &AttachmentStore,
    ) -> Result<SubmissionAcknowledgement, SubmissionError> {
        let commit = self.preparation_commit.clone().lock_owned().await;
        if operation.connection != self.snapshot().connection {
            return Ok(SubmissionAcknowledgement::Unmatched);
        }
        let checkout = operation
            .connection
            .workspace
            .checkout
            .clone()
            .ok_or(WorkspaceError::MissingCheckout)?;
        let request = operation.request;
        let thread = thread.clone();
        let store = store.clone();
        tokio::task::spawn_blocking(move || {
            let _commit = commit;
            checkout.revalidate()?;
            Ok(store.acknowledge_submission(request, &thread, outcome, &checkout)?)
        })
        .await?
    }
}

fn reply_outcome(
    kind: &SubmissionKind,
    request: RequestId,
    response: &Result<Value, RequestError>,
) -> Option<JournalOutcome> {
    match (kind, response) {
        (SubmissionKind::Turn, Ok(reply)) => Some(JournalOutcome::Accepted(TurnId(
            nonempty_string(&reply["turn"]["id"])?,
        ))),
        (SubmissionKind::Queue, Ok(reply)) => {
            let entry: QueueAddReply = serde_json::from_value(reply.clone()).ok()?;
            let entry = entry.queued_submission;
            (!entry.id.is_empty() && entry.client_user_message_id == request.0.to_string())
                .then_some(JournalOutcome::Queued(entry.id))
        }
        (SubmissionKind::Turn, Err(RequestError::Remote(error))) => {
            Some(JournalOutcome::Rejected { code: error.code })
        }
        // Internal errors can follow a committed queue write.
        (SubmissionKind::Queue, Err(RequestError::Remote(error)))
            if matches!(error.code, -32602..=-32600) =>
        {
            Some(JournalOutcome::Rejected { code: error.code })
        }
        _ => None,
    }
}

fn message_evidence(event: &ServerEvent) -> Option<(RequestId, ThreadId, TurnId)> {
    let ServerEvent::Notification { method, params } = event else {
        return None;
    };
    if !matches!(method.as_str(), "item/started" | "item/completed") {
        return None;
    }
    Some((
        message_client_id(&params["item"])?,
        ThreadId(nonempty_string(&params["threadId"])?),
        TurnId(nonempty_string(&params["turnId"])?),
    ))
}

pub(super) fn message_client_id(item: &Value) -> Option<RequestId> {
    if item["type"] != "userMessage" {
        return None;
    }
    Uuid::parse_str(item["clientId"].as_str()?)
        .ok()
        .map(RequestId)
}

fn nonempty_string(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

async fn dispatch(
    prepared: &PreparedThread,
    kind: &SubmissionKind,
    client: &AppServerClient,
    store: &AttachmentStore,
    timeout: Duration,
) -> Result<(Result<Value, RequestError>, SubmissionWrite), SubmissionError> {
    let intent = &prepared.intent;
    let owner = &intent.operation.connection;
    if client.identity() != owner {
        return Err(WorkspaceError::Retired.into());
    }
    let checkout = owner
        .workspace
        .checkout
        .as_ref()
        .ok_or(WorkspaceError::MissingCheckout)?;
    checkout.revalidate()?;
    let cwd = checkout
        .canonical_path()
        .to_str()
        .ok_or(SubmissionError::NonUnicodePath)?;
    let journaled = turn_request(prepared, cwd)?;
    let (method, request, queue_add) = match kind {
        SubmissionKind::Turn => ("turn/start", journaled.clone(), false),
        SubmissionKind::Queue => (
            "thread/queue/add",
            json!({
                "threadId": journaled["threadId"],
                "clientUserMessageId": journaled["clientUserMessageId"],
                "input": journaled["input"],
            }),
            true,
        ),
    };

    let id = intent.operation.request;
    let captured = intent.clone();
    let journal = store.clone();
    let thread = prepared.thread.clone();
    let captured_checkout = checkout.clone();
    let write = tokio::task::spawn_blocking(move || {
        journal.reserve_submission(JournalEntry {
            id,
            thread: &thread,
            draft: captured.draft.id,
            revision: captured.draft.revision,
            request: &journaled,
            attachments: &captured.draft.attachments,
            checkout: &captured_checkout,
            queue_add,
        })
    })
    .await??;

    let response = if *prepared.stopped.borrow() {
        Err(RequestError::Stopped(Delivery::Unsent))
    } else {
        let journal = store.clone();
        tokio::task::spawn_blocking(move || {
            journal.set_submission_phase(id, JournalPhase::Dispatching)
        })
        .await??;
        client
            .request_scoped(
                method,
                request,
                timeout,
                checkout.clone(),
                prepared.stopped.clone(),
            )
            .await
    };
    if response.as_ref().is_err_and(RequestError::is_unsent) {
        let journal = store.clone();
        tokio::task::spawn_blocking(move || journal.set_submission_phase(id, JournalPhase::Unsent))
            .await??;
    }
    Ok((response, write))
}

fn turn_request(prepared: &PreparedThread, cwd: &str) -> Result<Value, SubmissionError> {
    let intent = &prepared.intent;
    let mut input = Vec::new();
    if !intent.draft.text.is_empty() {
        input.push(json!({ "type": "text", "text": intent.draft.text }));
    }
    input.extend(intent.draft.context.iter().cloned());
    for attachment in &intent.draft.attachments {
        let path = attachment.path();
        let path = path.to_str().ok_or(SubmissionError::NonUnicodePath)?;
        input.push(json!({ "type": "localImage", "path": path }));
    }
    let settings = &intent.settings;
    Ok(json!({
        "threadId": prepared.thread.0,
        "cwd": cwd,
        "clientUserMessageId": intent.operation.request.0.to_string(),
        "input": input,
        "model": settings.model,
        "effort": settings.reasoning_effort,
        "serviceTierForTurn": settings.service_tier,
        "approvalPolicy": settings.approval_policy,
        "approvalsReviewer": settings.approvals_reviewer,
        "sandboxPolicy": settings.sandbox_policy,
        "collaborationMode": settings.collaboration_mode,
    }))
}
