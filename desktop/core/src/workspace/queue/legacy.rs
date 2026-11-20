use std::{sync::Arc, time::Duration};

use super::{QueueError, WorkspaceEngine};
use crate::{
    codex::{AppServerClient, ChatRead, QueueSnapshot, RequestError},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{AttachmentStore, JournalEntry, JournalKind, JournalOutcome},
    workspace::{
        ExecutionTarget, SendIntent, SubmissionError, WorkspaceError, submission::turn_request,
    },
};

#[derive(Debug, Eq, PartialEq)]
pub enum LegacyStartResult {
    Started(TurnId),
    ActiveTurn,
    NotReady,
}

impl WorkspaceEngine {
    pub async fn enqueue_legacy_follow_up(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        target: ExecutionTarget,
        evidence: &ChatRead<QueueSnapshot>,
        intent: Arc<SendIntent>,
    ) -> Result<RequestId, QueueError> {
        let owner = client.identity();
        require_legacy_queue(owner, &target.thread, evidence)?;
        if &intent.operation.connection != owner {
            return Err(WorkspaceError::Retired.into());
        }
        if !intent.draft.has_content() {
            return Err(WorkspaceError::EmptyDraft.into());
        }
        let _queue = self.lock_queue(&target.thread).await;
        let commit = self.preparation_commit.clone().lock_owned().await;
        let checkout = self.queue_owner(owner, &target.thread)?;
        if !self.snapshot().execution.active_turns.contains(&target) {
            return Err(WorkspaceError::InactiveTurn.into());
        }
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(SubmissionError::NonUnicodePath)?;
        let request = turn_request(&intent, &target.thread, cwd)?;
        let id = intent.operation.request;
        let journal = store.clone();
        tokio::task::spawn_blocking(move || {
            let _commit = commit;
            let _reservation = journal.reserve_submission(JournalEntry {
                id,
                thread: &target.thread,
                draft: intent.draft.id,
                revision: intent.draft.revision,
                request: &request,
                attachments: &intent.draft.attachments,
                checkout: &checkout,
                kind: JournalKind::LegacyQueue(&intent.operation.connection),
            })?;
            Ok::<_, QueueError>(id)
        })
        .await
        .map_err(SubmissionError::from)?
    }

    pub async fn start_legacy_queue(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        evidence: &ChatRead<QueueSnapshot>,
        resume: Option<RequestId>,
        timeout: Duration,
    ) -> Result<LegacyStartResult, QueueError> {
        let owner = client.identity();
        require_legacy_queue(owner, thread, evidence)?;
        let _queue = self.lock_queue(thread).await;
        let (checkout, ready) = {
            let _commit = self.preparation_commit.lock().await;
            let checkout = self.queue_owner(owner, thread)?;
            if self.thread_has_active_turn(thread) {
                return Ok(LegacyStartResult::ActiveTurn);
            }
            let ready = store.claim_legacy_dispatch(&checkout, thread, owner, resume)?;
            (checkout, ready)
        };
        let Some(ready) = ready else {
            return Ok(LegacyStartResult::NotReady);
        };
        let response = self
            .write_queue(client, thread, "turn/start", ready.request.clone(), timeout)
            .await;
        let turn = match response {
            Ok(reply) => {
                if let Some(turn) = reply["turn"]["id"].as_str().filter(|id| !id.is_empty()) {
                    TurnId(turn.to_owned())
                } else {
                    store.fail_legacy_dispatch(&checkout, thread, ready.id, false)?;
                    return Err(QueueError::InvalidReceipt);
                }
            }
            Err(error) => {
                let definitely_unsent = matches!(&error, QueueError::Request(request) if request.is_unsent()
                    || matches!(request, RequestError::Remote(error) if matches!(error.code, -32602..=-32600)));
                store.fail_legacy_dispatch(&checkout, thread, ready.id, definitely_unsent)?;
                return Err(error);
            }
        };
        let operation = OperationIdentity {
            connection: owner.clone(),
            request: ready.id,
        };
        self.acknowledge(
            &operation,
            thread,
            JournalOutcome::Accepted(turn.clone()),
            store,
        )
        .await?;
        Ok(LegacyStartResult::Started(turn))
    }

    pub(in crate::workspace) async fn pause_legacy_queue(
        &self,
        owner: &ConnectionIdentity,
        store: &AttachmentStore,
        thread: &ThreadId,
    ) -> Result<(), QueueError> {
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(owner, thread)?;
        Ok(store.pause_legacy_queue(&checkout, thread)?)
    }
}

fn require_legacy_queue(
    owner: &ConnectionIdentity,
    thread: &ThreadId,
    evidence: &ChatRead<QueueSnapshot>,
) -> Result<(), QueueError> {
    match evidence.for_selection(owner, thread)? {
        QueueSnapshot::Unsupported => Ok(()),
        QueueSnapshot::Available(_) => Err(QueueError::ServerQueueAvailable),
    }
}
