use std::{sync::Arc, time::Duration};

use super::{QueueEditResult, QueueError, WorkspaceEngine, edited_input};
use crate::{
    checkout::CheckoutIdentity,
    codex::{AppServerClient, ChatRead, QueueSnapshot, QueuedSubmission, RequestError},
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::attachments::{
        AttachmentStore, JournalEntry, JournalKind, JournalOutcome, LegacyQueueStatus,
        queue_edits::{QueueEdit, QueueEditError, QueueEditOutcome},
    },
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
    pub async fn edit_local_follow_up(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        evidence: &ChatRead<QueueSnapshot>,
        id: RequestId,
    ) -> Result<(), QueueError> {
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.legacy_owner(client, thread, evidence)?;
        let entry = local_entry(store, &checkout, thread, client.identity(), id)?
            .ok_or(QueueError::Changed)?;
        store.begin_queue_edit(&checkout, thread, entry)?;
        Ok(())
    }

    pub async fn cancel_local_follow_up_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        edit: &QueueEdit,
        evidence: &ChatRead<QueueSnapshot>,
    ) -> Result<(), QueueError> {
        let thread = &edit.thread;
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.legacy_owner(client, thread, evidence)?;
        let id = local_edit_id(edit)?;
        let outcome = if local_entry(store, &checkout, thread, client.identity(), id)?.is_some() {
            QueueEditOutcome::Discard
        } else {
            QueueEditOutcome::Detach
        };
        Ok(store.finish_queue_edit(&checkout, edit, outcome)?)
    }

    pub async fn save_local_follow_up_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        edit: &QueueEdit,
        evidence: &ChatRead<QueueSnapshot>,
    ) -> Result<QueueEditResult, QueueError> {
        let thread = &edit.thread;
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.legacy_owner(client, thread, evidence)?;
        let id = local_edit_id(edit)?;
        let Some(mut entry) = local_entry(store, &checkout, thread, client.identity(), id)? else {
            store.finish_queue_edit(&checkout, edit, QueueEditOutcome::Detach)?;
            return Ok(QueueEditResult::Detached);
        };
        if entry != edit.entry {
            return Err(QueueError::Changed);
        }
        let draft = store.capture_queue_edit(&checkout, edit)?;
        if draft.text.trim().is_empty() && draft.context.is_empty() {
            return Err(QueueEditError::InvalidInput.into());
        }
        entry.input = edited_input(&entry, &draft);
        store.finish_queue_edit(
            &checkout,
            edit,
            QueueEditOutcome::Updated {
                entry,
                revision: draft.revision,
                legacy: true,
            },
        )?;
        Ok(QueueEditResult::Updated)
    }

    pub async fn delete_local_follow_up(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        evidence: &ChatRead<QueueSnapshot>,
        id: RequestId,
    ) -> Result<(), QueueError> {
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.legacy_owner(client, thread, evidence)?;
        Ok(store.delete_local_follow_up(&checkout, thread, id)?)
    }

    pub async fn reorder_local_follow_ups(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        evidence: &ChatRead<QueueSnapshot>,
        order: &[RequestId],
    ) -> Result<(), QueueError> {
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.legacy_owner(client, thread, evidence)?;
        Ok(store.reorder_local_follow_ups(&checkout, thread, order)?)
    }

    fn legacy_owner(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        evidence: &ChatRead<QueueSnapshot>,
    ) -> Result<CheckoutIdentity, QueueError> {
        require_legacy_queue(client.identity(), thread, evidence)?;
        self.queue_owner(client.identity(), thread)
    }

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
        let _queue = self.lock_queue(thread).await;
        if matches!(
            evidence.for_selection(owner, thread)?,
            QueueSnapshot::Available(_)
        ) {
            if resume.is_none() {
                return Err(QueueError::ServerQueueAvailable);
            }
            if !self.read_queue(client, thread, timeout).await?.is_empty() {
                return Ok(LegacyStartResult::NotReady);
            }
        }
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

pub(super) fn require_legacy_queue(
    owner: &ConnectionIdentity,
    thread: &ThreadId,
    evidence: &ChatRead<QueueSnapshot>,
) -> Result<(), QueueError> {
    match evidence.for_selection(owner, thread)? {
        QueueSnapshot::Unsupported => Ok(()),
        QueueSnapshot::Available(_) => Err(QueueError::ServerQueueAvailable),
    }
}

fn local_edit_id(edit: &QueueEdit) -> Result<RequestId, QueueError> {
    uuid::Uuid::parse_str(&edit.entry.id)
        .map(RequestId)
        .map_err(|_| QueueError::Changed)
}

fn local_entry(
    store: &AttachmentStore,
    checkout: &CheckoutIdentity,
    thread: &ThreadId,
    owner: &ConnectionIdentity,
    id: RequestId,
) -> Result<Option<QueuedSubmission>, QueueError> {
    Ok(store
        .legacy_queue(checkout, thread, owner)?
        .into_iter()
        .find(|entry| entry.id == id && entry.status != LegacyQueueStatus::AwaitingEvidence)
        .map(|entry| {
            let id = entry.id.0.to_string();
            QueuedSubmission {
                id: id.clone(),
                client_user_message_id: id,
                input: entry.input,
            }
        }))
}
