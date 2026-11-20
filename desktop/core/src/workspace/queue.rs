use std::{
    collections::HashSet,
    sync::{Arc, Weak},
    time::Duration,
};

use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::{Mutex, OwnedMutexGuard, watch};
use uuid::Uuid;

mod legacy;
pub use legacy::LegacyStartResult;
mod steering;
pub use steering::QueuedSteerResult;

use super::{SubmissionError, WorkspaceAction, WorkspaceEngine, WorkspaceError};
use crate::{
    checkout::{CheckoutError, CheckoutIdentity},
    codex::{
        AppServerClient, BrowseError, ChatRead, CodexBrowser, QueueSnapshot, QueuedSubmission,
        RequestError,
    },
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId, TurnId},
    storage::{
        attachments::{
            AttachmentStore, JournalOutcome,
            queue_edits::{QueueEdit, QueueEditError, QueueEditOutcome},
        },
        drafts::StoredDraft,
    },
};

#[derive(Debug, Error)]
pub enum QueueError {
    #[error(transparent)]
    Workspace(#[from] WorkspaceError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Browse(#[from] BrowseError),
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Edit(#[from] QueueEditError),
    #[error("the server does not support the thread queue")]
    Unsupported,
    #[error("the server owns the queue for this thread")]
    ServerQueueAvailable,
    #[error("the captured queue changed")]
    Changed,
    #[error("the server returned an invalid queue mutation receipt")]
    InvalidReceipt,
    #[error(transparent)]
    Journal(#[from] crate::storage::attachments::JournalError),
    #[error(transparent)]
    Submission(#[from] SubmissionError),
}

#[derive(Debug, Eq, PartialEq)]
pub enum QueueEditResult {
    Updated,
    Detached,
}

#[derive(Debug, Eq, PartialEq)]
pub enum QueueDeleteResult {
    Deleted,
    NotConfirmed,
}

#[derive(Debug, Eq, PartialEq)]
pub enum QueueStartResult {
    Started(TurnId),
    ActiveTurn,
    Missing,
}

impl WorkspaceEngine {
    pub async fn start_queue_entry(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<QueueStartResult, QueueError> {
        let _queue = self.lock_queue(thread).await;
        let owner = client.identity();
        self.require_unreserved(client, store, thread, &entry.client_user_message_id)?;
        if self.thread_has_active_turn(thread) {
            return Ok(QueueStartResult::ActiveTurn);
        }
        if !self
            .has_captured_entry(client, thread, entry, timeout)
            .await?
        {
            return Ok(QueueStartResult::Missing);
        }
        if self.thread_has_active_turn(thread) {
            return Ok(QueueStartResult::ActiveTurn);
        }
        let response = self
            .write_queue(
                client,
                thread,
                "thread/queue/start",
                json!({"threadId":thread.0,"queuedSubmissionId":entry.id}),
                timeout,
            )
            .await;
        let reply = match response {
            Ok(reply) => reply,
            Err(QueueError::Request(RequestError::Remote(error)))
                if error.code == -32600
                    && error.message == "thread already has an active or pending turn" =>
            {
                return Ok(QueueStartResult::ActiveTurn);
            }
            Err(QueueError::Request(RequestError::Remote(error)))
                if error.code == -32600
                    && error.message == format!("queued submission not found: {}", entry.id) =>
            {
                return Ok(QueueStartResult::Missing);
            }
            Err(error) => return Err(error),
        };
        let turn = reply["turn"]["id"]
            .as_str()
            .filter(|id| !id.is_empty() && reply["turn"]["status"] == "inProgress")
            .map(|id| TurnId(id.to_owned()))
            .ok_or(QueueError::InvalidReceipt)?;
        if let Ok(request) = Uuid::parse_str(&entry.client_user_message_id) {
            let operation = OperationIdentity {
                connection: owner.clone(),
                request: RequestId(request),
            };
            self.acknowledge(
                &operation,
                thread,
                JournalOutcome::Accepted(turn.clone()),
                store,
            )
            .await?;
        }
        self.note_queue_consumption(owner, store, thread, &turn, &entry.client_user_message_id)
            .await?;
        // Execution events are authoritative and may have already reported completion.
        Ok(QueueStartResult::Started(turn))
    }

    fn thread_has_active_turn(&self, thread: &ThreadId) -> bool {
        self.snapshot()
            .execution
            .active_turns
            .iter()
            .any(|turn| &turn.thread == thread)
    }

    pub async fn delete_queue_entry(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<QueueDeleteResult, QueueError> {
        let _queue = self.lock_queue(thread).await;
        self.require_unreserved(client, store, thread, &entry.client_user_message_id)?;
        if !self
            .has_captured_entry(client, thread, entry, timeout)
            .await?
        {
            return Ok(QueueDeleteResult::NotConfirmed);
        }
        let reply = self
            .write_queue(
                client,
                thread,
                "thread/queue/delete",
                json!({"threadId":thread.0,"queuedSubmissionId":entry.id}),
                timeout,
            )
            .await?;
        match reply["deleted"].as_bool() {
            Some(true) => {
                let _commit = self.preparation_commit.lock().await;
                let checkout = self.queue_owner(client.identity(), thread)?;
                store.record_queue_deletion(&checkout, thread, entry)?;
                Ok(QueueDeleteResult::Deleted)
            }
            Some(false) => Ok(QueueDeleteResult::NotConfirmed),
            None => Err(QueueError::InvalidReceipt),
        }
    }

    pub async fn begin_queue_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<QueueEdit, QueueError> {
        let _queue = self.lock_queue(thread).await;
        self.require_unreserved(client, store, thread, &entry.client_user_message_id)?;
        if !self
            .has_captured_entry(client, thread, entry, timeout)
            .await?
        {
            return Err(QueueError::Changed);
        }
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(client.identity(), thread)?;
        Ok(store.begin_queue_edit(&checkout, thread, entry.clone())?)
    }

    pub async fn cancel_queue_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        edit: &QueueEdit,
        timeout: Duration,
    ) -> Result<(), QueueError> {
        let _queue = self.lock_queue(&edit.thread).await;
        let entries = self.read_queue(client, &edit.thread, timeout).await?;
        let outcome = if find_entry(&entries, &edit.entry)?.is_some() {
            QueueEditOutcome::Discard
        } else {
            QueueEditOutcome::Detach
        };
        self.settle_queue_edit(client, store, edit, outcome).await
    }

    pub async fn save_queue_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        edit: &QueueEdit,
        timeout: Duration,
    ) -> Result<QueueEditResult, QueueError> {
        let _queue = self.lock_queue(&edit.thread).await;
        self.require_unreserved(
            client,
            store,
            &edit.thread,
            &edit.entry.client_user_message_id,
        )?;
        let checkout = self.queue_owner(client.identity(), &edit.thread)?;
        let draft = store.capture_queue_edit(&checkout, edit)?;
        let entries = self.read_queue(client, &edit.thread, timeout).await?;
        let Some(current) = find_entry(&entries, &edit.entry)? else {
            self.settle_queue_edit(client, store, edit, QueueEditOutcome::Detach)
                .await?;
            return Ok(QueueEditResult::Detached);
        };
        if current != &edit.entry {
            return Err(QueueError::Changed);
        }
        if draft.text.trim().is_empty() && draft.context.is_empty() {
            return Err(QueueEditError::InvalidInput.into());
        }
        let input = edited_input(&edit.entry, &draft);
        let updated =
            if input == current.input {
                current.clone()
            } else {
                let response = self.write_queue(
                client, &edit.thread, "thread/queue/update",
                json!({"threadId":edit.thread.0,"queuedSubmissionId":current.id,"input":input}),
                timeout,
            ).await;
                match response {
                    Ok(result) => {
                        let entry: QueuedSubmission =
                            serde_json::from_value(result["queuedSubmission"].clone())
                                .map_err(|_| QueueError::InvalidReceipt)?;
                        if !same_entry(&entry, current) {
                            return Err(QueueError::InvalidReceipt);
                        }
                        entry
                    }
                    Err(error) => {
                        let latest = self.read_queue(client, &edit.thread, timeout).await;
                        match latest.as_deref() {
                            Ok(entries) => match find_entry(entries, current)? {
                                None => {
                                    self.settle_queue_edit(
                                        client,
                                        store,
                                        edit,
                                        QueueEditOutcome::Detach,
                                    )
                                    .await?;
                                    return Ok(QueueEditResult::Detached);
                                }
                                Some(entry) if entry.input == input => entry.clone(),
                                _ => return Err(error),
                            },
                            Err(_) => return Err(error),
                        }
                    }
                }
            };
        self.settle_queue_edit(
            client,
            store,
            edit,
            QueueEditOutcome::Updated {
                entry: updated,
                revision: draft.revision,
            },
        )
        .await?;
        Ok(QueueEditResult::Updated)
    }

    pub async fn reorder_queue(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        captured: &ChatRead<QueueSnapshot>,
        ordered_ids: &[String],
        timeout: Duration,
    ) -> Result<Vec<QueuedSubmission>, QueueError> {
        let _queue = self.lock_queue(thread).await;
        let QueueSnapshot::Available(captured) =
            captured.for_selection(client.identity(), thread)?
        else {
            return Err(QueueError::Unsupported);
        };
        let current = self.read_queue(client, thread, timeout).await?;
        let member_ids: HashSet<_> = current.iter().map(|entry| &entry.id).collect();
        if current.len() != captured.len()
            || !current
                .iter()
                .zip(captured)
                .all(|(live, old)| same_entry(live, old))
            || ordered_ids.len() != current.len()
            || ordered_ids.iter().collect::<HashSet<_>>() != member_ids
        {
            return Err(QueueError::Changed);
        }
        if current.iter().map(|entry| &entry.id).eq(ordered_ids) {
            return Ok(current);
        }
        let written = self
            .write_queue(
                client,
                thread,
                "thread/queue/reorder",
                json!({"threadId":thread.0,"queuedSubmissionIds":ordered_ids}),
                timeout,
            )
            .await;
        let refreshed = self.read_queue(client, thread, timeout).await;
        match written {
            Ok(_) => refreshed,
            Err(error) => {
                let current = refreshed?;
                if current.iter().map(|entry| &entry.id).eq(ordered_ids) {
                    Ok(current)
                } else {
                    Err(error)
                }
            }
        }
    }

    pub(super) async fn note_queue_consumption(
        &self,
        owner: &ConnectionIdentity,
        store: &AttachmentStore,
        thread: &ThreadId,
        turn: &TurnId,
        client_id: &str,
    ) -> Result<(), QueueError> {
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(owner, thread)?;
        store.observe_steering_message(&checkout, thread, turn, client_id)?;
        Ok(store.detach_consumed_queue_edit(&checkout, thread, client_id)?)
    }

    pub async fn reconcile_queue_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        queue: &ChatRead<QueueSnapshot>,
    ) -> Result<(), QueueError> {
        let owner = client.identity();
        let QueueSnapshot::Available(entries) = queue.for_selection(owner, thread)? else {
            return Ok(());
        };
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(owner, thread)?;
        if let Some(edit) = store.queue_edit(&checkout, thread)?
            && find_entry(entries, &edit.entry)?.is_none()
        {
            store.finish_queue_edit(&checkout, &edit, QueueEditOutcome::Detach)?;
        }
        Ok(())
    }

    async fn settle_queue_edit(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        edit: &QueueEdit,
        outcome: QueueEditOutcome,
    ) -> Result<(), QueueError> {
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(client.identity(), &edit.thread)?;
        Ok(store.finish_queue_edit(&checkout, edit, outcome)?)
    }

    fn queue_owner(
        &self,
        owner: &ConnectionIdentity,
        thread: &ThreadId,
    ) -> Result<CheckoutIdentity, QueueError> {
        let state = self.snapshot();
        if &state.connection != owner {
            return Err(WorkspaceError::Retired.into());
        }
        if !state.writable_threads.contains(thread) {
            return Err(WorkspaceError::UnownedExecution.into());
        }
        let checkout = owner
            .workspace
            .checkout
            .clone()
            .ok_or(WorkspaceError::MissingCheckout)?;
        checkout.revalidate()?;
        Ok(checkout)
    }

    async fn has_captured_entry(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<bool, QueueError> {
        let entries = self.read_queue(client, thread, timeout).await?;
        match find_entry(&entries, entry)? {
            Some(current) if current == entry => Ok(true),
            Some(_) => Err(QueueError::Changed),
            None => Ok(false),
        }
    }

    async fn read_queue(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<Vec<QueuedSubmission>, QueueError> {
        let owner = client.identity();
        self.queue_owner(owner, thread)?;
        let browser = CodexBrowser::new(client.clone());
        let summary = browser.thread_summary(thread, timeout).await?;
        let queue = browser.queue_snapshot(&summary, timeout).await?;
        self.queue_owner(owner, thread)?;
        match queue.into_for_selection(owner, thread)? {
            QueueSnapshot::Available(entries) => Ok(entries),
            QueueSnapshot::Unsupported => Err(QueueError::Unsupported),
        }
    }

    async fn write_queue(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<Value, QueueError> {
        self.write_queue_for_turn(client, thread, None, method, params, timeout)
            .await
    }

    async fn write_queue_for_turn(
        &self,
        client: &AppServerClient,
        thread: &ThreadId,
        active_turn: Option<TurnId>,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<Value, QueueError> {
        let checkout = self.queue_owner(client.identity(), thread)?;
        let operation = OperationIdentity {
            connection: client.identity().clone(),
            request: RequestId(Uuid::new_v4()),
        };
        let (stop, stopped) = watch::channel(false);
        self.apply(WorkspaceAction::ReserveThreadSubmission {
            operation: operation.clone(),
            thread: thread.clone(),
            active_turn,
            stopped: stop,
        })
        .await?;
        let result = client
            .request_scoped(method, params, timeout, checkout, stopped)
            .await;
        self.apply(WorkspaceAction::SubmissionFinished { operation })
            .await?;
        Ok(result?)
    }

    pub(super) async fn lock_queue(&self, thread: &ThreadId) -> OwnedMutexGuard<()> {
        let lock = {
            let mut locks = self
                .queue_locks
                .lock()
                .expect("queue lock registry poisoned");
            locks.retain(|_, lock| lock.strong_count() > 0);
            if let Some(lock) = locks.get(thread).and_then(Weak::upgrade) {
                lock
            } else {
                let lock = Arc::new(Mutex::new(()));
                locks.insert(thread.clone(), Arc::downgrade(&lock));
                lock
            }
        };
        lock.lock_owned().await
    }
}

fn same_entry(a: &QueuedSubmission, b: &QueuedSubmission) -> bool {
    a.id == b.id && a.client_user_message_id == b.client_user_message_id
}

fn find_entry<'a>(
    entries: &'a [QueuedSubmission],
    target: &QueuedSubmission,
) -> Result<Option<&'a QueuedSubmission>, QueueError> {
    let mut matching = entries.iter().filter(|entry| {
        entry.id == target.id || entry.client_user_message_id == target.client_user_message_id
    });
    match matching.next() {
        Some(entry) if same_entry(entry, target) && matching.next().is_none() => Ok(Some(entry)),
        Some(_) => Err(QueueError::Changed),
        None => Ok(None),
    }
}

fn edited_input(entry: &QueuedSubmission, draft: &StoredDraft) -> Vec<Value> {
    let mut input = Vec::new();
    if !draft.text.is_empty() {
        let original_text = entry
            .input
            .first()
            .filter(|first| first["type"] == "text" && first["text"] == draft.text);
        input.push(
            original_text
                .cloned()
                .unwrap_or_else(|| json!({"type":"text", "text":draft.text, "text_elements":[]})),
        );
    }
    input.extend(draft.context.iter().cloned());
    input
}
