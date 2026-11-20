use std::{
    collections::HashSet,
    sync::{Arc, Weak},
    time::Duration,
};

use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::{Mutex, OwnedMutexGuard, watch};
use uuid::Uuid;

use super::{WorkspaceAction, WorkspaceEngine, WorkspaceError};
use crate::{
    checkout::{CheckoutError, CheckoutIdentity},
    codex::{
        AppServerClient, BrowseError, ChatRead, CodexBrowser, QueueSnapshot, QueuedSubmission,
        RequestError,
    },
    identity::{ConnectionIdentity, OperationIdentity, RequestId, ThreadId},
    storage::{
        attachments::{
            AttachmentStore,
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
    #[error("the captured queue changed")]
    Changed,
    #[error("the server returned an invalid queue mutation receipt")]
    InvalidReceipt,
    #[error(transparent)]
    Journal(#[from] crate::storage::attachments::JournalError),
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

impl WorkspaceEngine {
    pub async fn delete_queue_entry(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        thread: &ThreadId,
        entry: &QueuedSubmission,
        timeout: Duration,
    ) -> Result<QueueDeleteResult, QueueError> {
        let _queue = self.lock_queue(thread).await;
        let entries = self.read_queue(client, thread, timeout).await?;
        let Some(current) = find_entry(&entries, entry)? else {
            return Ok(QueueDeleteResult::NotConfirmed);
        };
        if current != entry {
            return Err(QueueError::Changed);
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
        let entries = self.read_queue(client, thread, timeout).await?;
        if find_entry(&entries, entry)? != Some(entry) {
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

    pub(super) async fn detach_consumed_queue_edit(
        &self,
        owner: &ConnectionIdentity,
        store: &AttachmentStore,
        thread: &ThreadId,
        client_id: &str,
    ) -> Result<(), QueueError> {
        let _commit = self.preparation_commit.lock().await;
        let checkout = self.queue_owner(owner, thread)?;
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
        let checkout = self.queue_owner(client.identity(), thread)?;
        let operation = OperationIdentity {
            connection: client.identity().clone(),
            request: RequestId(Uuid::new_v4()),
        };
        let (stop, stopped) = watch::channel(false);
        self.apply(WorkspaceAction::ReserveThreadSubmission {
            operation: operation.clone(),
            thread: thread.clone(),
            active_turn: None,
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
