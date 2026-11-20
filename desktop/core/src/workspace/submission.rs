use std::time::Duration;

use serde_json::{Value, json};
use thiserror::Error;
use uuid::Uuid;

use super::{
    PreparedThread, SubmissionAcknowledgement, WorkspaceAction, WorkspaceEngine, WorkspaceError,
};
use crate::{
    checkout::CheckoutError,
    codex::{AppServerClient, Delivery, RequestError, ServerEvent},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{
        AttachmentStore, JournalEntry, JournalError, JournalOutcome, JournalPhase,
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

impl WorkspaceEngine {
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
            let operation = prepared.intent.operation.clone();
            let outcome = async {
                let response = dispatch(&prepared, &client, &store, timeout).await?;
                let acknowledgement = match reply_outcome(&response) {
                    Some(outcome) => {
                        engine
                            .acknowledge(&operation, &prepared.thread, outcome, &store)
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
            let _ = engine
                .apply(WorkspaceAction::SubmissionFinished { operation })
                .await;
            outcome
        })
        .await?
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

    async fn acknowledge(
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
            Ok(store.acknowledge_submission(request, &thread, outcome)?)
        })
        .await?
    }
}

fn reply_outcome(response: &Result<Value, RequestError>) -> Option<JournalOutcome> {
    match response {
        Ok(reply) => Some(JournalOutcome::Accepted(TurnId(nonempty_string(
            &reply["turn"]["id"],
        )?))),
        Err(RequestError::Remote(error)) => Some(JournalOutcome::Rejected { code: error.code }),
        Err(_) => None,
    }
}

fn message_evidence(event: &ServerEvent) -> Option<(RequestId, ThreadId, TurnId)> {
    let ServerEvent::Notification { method, params } = event else {
        return None;
    };
    if !matches!(method.as_str(), "item/started" | "item/completed")
        || params["item"]["type"] != "userMessage"
    {
        return None;
    }
    let client = Uuid::parse_str(params["item"]["clientId"].as_str()?).ok()?;
    Some((
        RequestId(client),
        ThreadId(nonempty_string(&params["threadId"])?),
        TurnId(nonempty_string(&params["turnId"])?),
    ))
}

fn nonempty_string(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

async fn dispatch(
    prepared: &PreparedThread,
    client: &AppServerClient,
    store: &AttachmentStore,
    timeout: Duration,
) -> Result<Result<Value, RequestError>, SubmissionError> {
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
    let request = turn_request(prepared, cwd)?;

    let id = intent.operation.request;
    let captured = intent.clone();
    let journal = store.clone();
    let thread = prepared.thread.clone();
    let payload = request.clone();
    tokio::task::spawn_blocking(move || {
        journal.reserve_submission(JournalEntry {
            id,
            thread: &thread,
            draft: captured.draft.id,
            revision: captured.draft.revision,
            request: &payload,
            attachments: &captured.draft.attachments,
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
                "turn/start",
                request,
                timeout,
                checkout.clone(),
                prepared.stopped.clone(),
            )
            .await
    };
    if matches!(
        response,
        Err(RequestError::Stopped(Delivery::Unsent)
            | RequestError::Timeout(Delivery::Unsent)
            | RequestError::Disconnected(Delivery::Unsent)
            | RequestError::Encode(_)
            | RequestError::IdExhausted)
    ) {
        let journal = store.clone();
        tokio::task::spawn_blocking(move || journal.set_submission_phase(id, JournalPhase::Unsent))
            .await??;
    }
    Ok(response)
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
