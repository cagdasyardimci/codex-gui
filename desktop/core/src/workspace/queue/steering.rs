use std::time::Duration;

use serde_json::json;
use uuid::Uuid;

use super::{QueueError, WorkspaceEngine, legacy::require_legacy_queue};
use crate::{
    checkout::CheckoutIdentity,
    codex::{
        AppServerClient, ChatRead, CodexBrowser, QueueSnapshot, QueuedSubmission, RequestError,
    },
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::{
        attachments::{
            AttachmentStore, JournalOutcome, LegacyQueueStatus, QueueSteerPhase,
            QueueSteeringReceipt,
        },
        drafts::DraftId,
    },
    workspace::{
        ExecutionTarget, WorkspaceError,
        recovery::{Evidence, history_evidence},
        submission::message_client_key,
    },
};

#[derive(Debug, Eq, PartialEq)]
pub enum QueuedSteerResult {
    Steered,
    DeleteUnconfirmed,
}

impl WorkspaceEngine {
    pub async fn restore_detached_steering(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        id: RequestId,
    ) -> Result<DraftId, QueueError> {
        let _queue = self.lock_queue(thread).await;
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(client.identity(), thread)?;
        Ok(store.restore_detached_steering(&checkout, thread, id)?)
    }

    pub async fn steer_server_queue_entry(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        target: &ExecutionTarget,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<QueuedSteerResult, QueueError> {
        let _queue = self.lock_queue(&target.thread).await;
        let owner = client.identity();
        let thread = &target.thread;
        self.active_queue_owner(owner, target)?;
        self.require_unreserved(client, store, thread, &entry.client_user_message_id)?;
        if !self
            .has_captured_entry(client, thread, entry, timeout)
            .await?
        {
            return Err(QueueError::Changed);
        }
        let (checkout, journal) = {
            let _commit = self.preparation_commit.lock().await;
            let checkout = self.active_queue_owner(owner, target)?;
            let journal = store.reserve_queue_steering(
                &checkout,
                target,
                &entry.client_user_message_id,
                Some(&entry.id),
                &entry.input,
            )?;
            (checkout, journal)
        };
        let deleted = self
            .write_queue_for_turn(
                client,
                thread,
                Some(target.turn.clone()),
                "thread/queue/delete",
                json!({"threadId":thread.0,"queuedSubmissionId":entry.id}),
                timeout,
            )
            .await;
        match deleted {
            Ok(reply) => match reply["deleted"].as_bool() {
                Some(true) => {
                    if !store.transition_queue_steering(
                        &checkout,
                        journal.id,
                        QueueSteerPhase::Deleting,
                        Some(QueueSteerPhase::Detached),
                    )? {
                        return Ok(QueuedSteerResult::DeleteUnconfirmed);
                    }
                }
                Some(false) => return Ok(QueuedSteerResult::DeleteUnconfirmed),
                None => return Err(QueueError::InvalidReceipt),
            },
            Err(error) => {
                if definite_failure(&error) {
                    store.transition_queue_steering(
                        &checkout,
                        journal.id,
                        QueueSteerPhase::Deleting,
                        None,
                    )?;
                }
                return Err(error);
            }
        }
        self.send_queued_steering(client, store, &checkout, &journal, timeout)
            .await
    }

    pub async fn steer_legacy_queue_entry(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        target: &ExecutionTarget,
        evidence: &ChatRead<QueueSnapshot>,
        id: RequestId,
        timeout: Duration,
    ) -> Result<QueuedSteerResult, QueueError> {
        let owner = client.identity();
        require_legacy_queue(owner, &target.thread, evidence)?;
        let _queue = self.lock_queue(&target.thread).await;
        let (checkout, journal) = {
            let _commit = self.preparation_commit.lock().await;
            let checkout = self.active_queue_owner(owner, target)?;
            let entry = store
                .legacy_queue(&checkout, &target.thread, owner)?
                .into_iter()
                .find(|entry| entry.id == id && entry.status != LegacyQueueStatus::AwaitingEvidence)
                .ok_or(QueueError::Changed)?;
            let journal = store.reserve_queue_steering(
                &checkout,
                target,
                &id.0.to_string(),
                None,
                &entry.input,
            )?;
            (checkout, journal)
        };
        self.send_queued_steering(client, store, &checkout, &journal, timeout)
            .await
    }

    async fn send_queued_steering(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        checkout: &CheckoutIdentity,
        journal: &QueueSteeringReceipt,
        timeout: Duration,
    ) -> Result<QueuedSteerResult, QueueError> {
        let target = &journal.target;
        self.active_queue_owner(client.identity(), target)?;
        if !store.transition_queue_steering(
            checkout,
            journal.id,
            QueueSteerPhase::Detached,
            Some(QueueSteerPhase::Steering),
        )? {
            return Err(QueueError::Changed);
        }
        let steered = self
            .write_queue_for_turn(
                client,
                &target.thread,
                Some(target.turn.clone()),
                "turn/steer",
                json!({
                    "threadId":target.thread.0,"expectedTurnId":target.turn.0,
                    "clientUserMessageId":journal.client_id,"input":journal.input,
                }),
                timeout,
            )
            .await;
        match steered {
            Ok(reply) if reply["turnId"] == target.turn.0 => {
                self.settle_queued_steering(client.identity(), store, journal, &target.turn)
                    .await?;
                Ok(QueuedSteerResult::Steered)
            }
            Ok(_) => Err(QueueError::InvalidReceipt),
            Err(error) => {
                if definite_failure(&error) {
                    store.transition_queue_steering(
                        checkout,
                        journal.id,
                        QueueSteerPhase::Steering,
                        Some(QueueSteerPhase::Detached),
                    )?;
                }
                Err(error)
            }
        }
    }

    pub async fn recover_queued_steering(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<Vec<RequestId>, QueueError> {
        let owner = client.identity();
        let _queue = self.lock_queue(thread).await;
        let checkout = self.queue_owner(owner, thread)?;
        let mut entries = store.queue_steering_receipts(&checkout, thread)?;
        entries.retain(|entry| entry.phase != QueueSteerPhase::Detached);
        if entries.is_empty() {
            return Ok(Vec::new());
        }
        let browser = CodexBrowser::new(client.clone());
        let chat = browser.thread_summary(thread, timeout).await?;
        if entries
            .iter()
            .any(|entry| entry.phase == QueueSteerPhase::Deleting)
            && let Ok(queue) = browser.queue_snapshot(&chat, timeout).await
            && let QueueSnapshot::Available(current) = queue.for_selection(owner, thread)?
        {
            entries.retain(|entry| {
                entry.phase != QueueSteerPhase::Deleting
                    || !current.iter().any(|queued| {
                        Some(&queued.id) == entry.queued_id.as_ref()
                            && queued.client_user_message_id == entry.client_id
                    })
            });
        }
        if entries.is_empty() {
            return Ok(Vec::new());
        }
        let wanted: Vec<_> = entries
            .iter()
            .map(|entry| entry.client_id.clone())
            .collect();
        let evidence = history_evidence(&browser, &chat, owner, thread, &wanted, timeout, |item| {
            message_client_key(item).map(str::to_owned)
        })
        .await?;
        let mut recovered = Vec::new();
        for entry in entries {
            if let Some(Evidence::Unique(turn)) = evidence.get(&entry.client_id)
                && (entry.phase == QueueSteerPhase::Deleting || turn == &entry.target.turn)
            {
                self.settle_queued_steering(owner, store, &entry, turn)
                    .await?;
                recovered.push(entry.id);
            }
        }
        Ok(recovered)
    }

    async fn settle_queued_steering(
        &self,
        owner: &ConnectionIdentity,
        store: &AttachmentStore,
        journal: &QueueSteeringReceipt,
        turn: &TurnId,
    ) -> Result<(), QueueError> {
        if let Ok(id) = Uuid::parse_str(&journal.client_id) {
            let operation = OperationIdentity {
                connection: owner.clone(),
                request: RequestId(id),
            };
            self.acknowledge(
                &operation,
                &journal.target.thread,
                JournalOutcome::Accepted(turn.clone()),
                store,
            )
            .await?;
        }
        self.note_queue_consumption(
            owner,
            store,
            &journal.target.thread,
            turn,
            &journal.client_id,
        )
        .await
    }

    fn active_queue_owner(
        &self,
        owner: &ConnectionIdentity,
        target: &ExecutionTarget,
    ) -> Result<CheckoutIdentity, QueueError> {
        let checkout = self.queue_owner(owner, &target.thread)?;
        if !self.snapshot().execution.active_turns.contains(target) {
            return Err(WorkspaceError::InactiveTurn.into());
        }
        Ok(checkout)
    }

    pub(super) fn require_unreserved(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        client_id: &str,
    ) -> Result<(), QueueError> {
        let checkout = self.queue_owner(client.identity(), thread)?;
        if store.steering_is_reserved(&checkout, thread, client_id)? {
            return Err(QueueError::Changed);
        }
        Ok(())
    }
}

fn definite_failure(error: &QueueError) -> bool {
    matches!(error, QueueError::Workspace(WorkspaceError::InactiveTurn))
        || matches!(error, QueueError::Request(request) if request.is_unsent()
            || matches!(request, RequestError::Remote(error) if matches!(error.code, -32602..=-32600)))
}
