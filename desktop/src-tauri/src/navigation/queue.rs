use std::collections::{HashMap, HashSet};

use codex_gui_core::{
    codex::{AppServerClient, ChatRead, CodexBrowser, QueueSnapshot, QueuedSubmission},
    identity::{ConnectionIdentity, RequestId, ThreadId, TurnId},
    ipc::{
        IpcError, QueueCommand, QueueEditView, QueueEntryView, QueueRequest, QueueView, WriteAccess,
    },
    storage::attachments::{
        AttachmentStore, LegacyQueueStatus, QueueSteerPhase, queue_edits::QueueEdit,
    },
    workspace::{ExecutionTarget, SendIntent, WorkspaceEngine},
};

use super::{Failure, Navigation, RPC_TIMEOUT, report};
use serde_json::Value;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Default)]
pub(super) struct Queues {
    snapshots: HashMap<ThreadId, QueueCache>,
    jobs: HashMap<ThreadId, (Uuid, bool)>,
    changed: HashSet<ThreadId>,
    advance: HashSet<ThreadId>,
}

struct QueueCache {
    revision: Uuid,
    read: Arc<ChatRead<QueueSnapshot>>,
}

pub(super) struct QueueCompletion {
    owner: ConnectionIdentity,
    thread: ThreadId,
    job: Uuid,
    mutation: bool,
    result: Result<(), Failure>,
    snapshot: Result<ChatRead<QueueSnapshot>, Failure>,
}

enum Work {
    Refresh,
    Advance,
    Command(QueueCommand),
    FollowUp {
        intent: Arc<SendIntent>,
        target: ExecutionTarget,
        enabled: bool,
    },
}

impl Queues {
    pub(super) fn accept(&mut self, thread: ThreadId, read: ChatRead<QueueSnapshot>) {
        self.snapshots.insert(
            thread,
            QueueCache {
                revision: Uuid::new_v4(),
                read: Arc::new(read),
            },
        );
    }

    pub(super) fn knows(&self, thread: &ThreadId) -> bool {
        self.snapshots.contains_key(thread)
    }

    pub(super) fn has_mutations(&self) -> bool {
        self.jobs.values().any(|(_, mutation)| *mutation)
    }
}

impl Navigation {
    pub(super) fn handle_queue(&mut self, request: QueueRequest) -> Result<(), IpcError> {
        self.require(request.workspace_id)?;
        if self.view.write_access != WriteAccess::Ready
            || !self.view.account.permits_turns
            || self.view.selected_chat.as_ref() != Some(&request.chat_id)
        {
            return Err(IpcError::StaleSelection);
        }
        let view = self
            .view
            .queue
            .as_ref()
            .filter(|view| !view.busy && view.revision == request.revision)
            .ok_or(IpcError::StaleSelection)?;
        let thread = ThreadId(request.chat_id);
        if let QueueCommand::Enable(enabled) = request.command {
            let checkout = &self
                .selection
                .as_ref()
                .expect("authorized queue selection")
                .checkout;
            self.store
                .set_queue_enabled(checkout, &thread, enabled)
                .map_err(|error| report(error.into()))?;
            self.sync_actions();
            return Ok(());
        }
        if let QueueCommand::Steer(target) = &request.command
            && view.active_turn.as_ref() != Some(&target.turn_id)
        {
            return Err(IpcError::StaleSelection);
        }
        self.launch_queue_job(thread, Work::Command(request.command))
    }

    pub(super) fn send_follow_up(
        &mut self,
        intent: Arc<SendIntent>,
        target: ExecutionTarget,
    ) -> Result<(), Failure> {
        let view = self
            .view
            .queue
            .as_ref()
            .filter(|view| !view.busy && view.editing.is_none())
            .ok_or("the queue is no longer available for this draft")?;
        let work = Work::FollowUp {
            intent,
            target: target.clone(),
            enabled: view.enabled,
        };
        self.launch_queue_job(target.thread, work)
            .map_err(|error| format!("{error:?}").into())
    }

    pub(super) fn refresh_queue(&mut self, thread: ThreadId) {
        if self.queues.jobs.contains_key(&thread) {
            self.queues.changed.insert(thread);
        } else {
            let _ = self.launch_queue_job(thread, Work::Refresh);
        }
    }

    pub(super) fn advance_legacy_queue(&mut self, thread: ThreadId) {
        let Some(backend) = &self.backend else {
            return;
        };
        let client = backend.connection.client();
        let legacy = self.queues.snapshots.get(&thread).is_some_and(|cache| {
            matches!(
                cache.read.for_selection(client.identity(), &thread),
                Ok(QueueSnapshot::Unsupported)
            )
        });
        if !legacy || self.quit.is_some() || self.view.write_access != WriteAccess::Ready {
            return;
        }
        if self.queues.jobs.contains_key(&thread) {
            self.queues.advance.insert(thread);
        } else {
            let _ = self.launch_queue_job(thread, Work::Advance);
        }
    }

    fn launch_queue_job(&mut self, thread: ThreadId, work: Work) -> Result<(), IpcError> {
        let backend = self.backend.as_ref().ok_or(IpcError::ProjectUnavailable)?;
        let client = backend.connection.client();
        let owner = client.identity().clone();
        if self.queues.jobs.contains_key(&thread)
            || !backend.engine.snapshot().writable_threads.contains(&thread)
        {
            return Err(IpcError::StaleSelection);
        }
        let captured = self
            .queues
            .snapshots
            .get(&thread)
            .map(|cache| cache.read.clone());
        let mutation = !matches!(work, Work::Refresh);
        let job = Uuid::new_v4();
        self.queues.jobs.insert(thread.clone(), (job, mutation));
        let engine = backend.engine.clone();
        let store = self.store.clone();
        let completions = self.queue_completions.clone();
        tauri::async_runtime::spawn(async move {
            let result =
                apply_queue_work(&engine, &client, &store, &thread, captured.as_deref(), work)
                    .await;
            let snapshot = read_queue(&engine, &client, &store, &thread).await;
            let _ = completions
                .send(Box::new(QueueCompletion {
                    owner,
                    thread,
                    job,
                    mutation,
                    result,
                    snapshot,
                }))
                .await;
        });
        self.sync_actions();
        Ok(())
    }

    pub(super) fn complete_queue(&mut self, completion: QueueCompletion) {
        let QueueCompletion {
            owner,
            thread,
            job,
            mutation,
            result,
            snapshot,
        } = completion;
        if self
            .backend
            .as_ref()
            .is_none_or(|backend| backend.engine.snapshot().connection != owner)
            || self
                .queues
                .jobs
                .get(&thread)
                .is_none_or(|(active, _)| *active != job)
        {
            return;
        }
        self.queues.jobs.remove(&thread);
        if let Err(error) = result {
            eprintln!("{error}");
        }
        match snapshot {
            Ok(snapshot) => self.queues.accept(thread.clone(), snapshot),
            Err(error) => {
                eprintln!("{error}");
                self.queues.snapshots.remove(&thread);
            }
        }
        if mutation
            && self
                .selection
                .as_ref()
                .and_then(|selection| selection.thread.as_ref())
                == Some(&thread)
            && let Some(draft) = self.editor_id()
        {
            self.refresh_draft_after_submission(draft);
        } else {
            self.sync_actions();
        }
        let changed = self.queues.changed.remove(&thread);
        if self.queues.advance.remove(&thread) {
            self.advance_legacy_queue(thread);
        } else if changed {
            self.refresh_queue(thread);
        }
    }

    pub(super) fn queue_view(&self) -> Result<Option<QueueView>, Failure> {
        if self.view.write_access != WriteAccess::Ready || !self.view.account.permits_turns {
            return Ok(None);
        }
        let (Some(backend), Some(selection)) = (&self.backend, &self.selection) else {
            return Ok(None);
        };
        let Some(thread) = &selection.thread else {
            return Ok(None);
        };
        let Some(cache) = self.queues.snapshots.get(thread) else {
            return Ok(None);
        };
        let state = backend.engine.snapshot();
        let data = cache.read.for_selection(&state.connection, thread)?;
        let checkout = &selection.checkout;
        let editing = self.store.queue_edit(checkout, thread)?;
        let receipts = self.store.queue_steering_receipts(checkout, thread)?;
        let reserved = |client_id: &str| {
            editing
                .as_ref()
                .is_some_and(|edit| edit.entry.client_user_message_id == client_id)
                || receipts
                    .iter()
                    .any(|receipt| receipt.client_id == client_id)
        };
        let entries: Vec<_> = match data {
            QueueSnapshot::Available(rows) => rows
                .iter()
                .map(|entry| QueueEntryView {
                    id: entry.id.clone(),
                    text: queue_text(&entry.input),
                    reserved: reserved(&entry.client_user_message_id),
                })
                .collect(),
            QueueSnapshot::Unsupported => self
                .store
                .legacy_queue(checkout, thread, &state.connection)?
                .into_iter()
                .map(|entry| {
                    let id = entry.id.0.to_string();
                    let reserved =
                        entry.status == LegacyQueueStatus::AwaitingEvidence || reserved(&id);
                    QueueEntryView {
                        id,
                        text: queue_text(&entry.input),
                        reserved,
                    }
                })
                .collect(),
        };
        let active_turn = state
            .execution
            .active_turns
            .iter()
            .find(|turn| &turn.thread == thread)
            .map(|turn| turn.turn.0.clone());
        let resume = if active_turn.is_none() {
            entries
                .first()
                .filter(|entry| !entry.reserved)
                .map(|entry| entry.id.clone())
        } else {
            None
        };
        let editing = editing
            .map(|edit| {
                self.store
                    .read_editor_draft(edit.draft)
                    .map(|draft| QueueEditView {
                        id: edit.id.to_string(),
                        has_context: !draft.context.is_empty(),
                    })
            })
            .transpose()?;
        let detached = receipts
            .iter()
            .filter(|receipt| receipt.phase == QueueSteerPhase::Detached)
            .map(|receipt| QueueEntryView {
                id: receipt.id.0.to_string(),
                text: queue_text(&receipt.input),
                reserved: false,
            })
            .collect();
        Ok(Some(QueueView {
            revision: cache.revision.to_string(),
            enabled: self.store.queue_enabled(checkout, thread)?,
            busy: self.queues.jobs.contains_key(thread),
            active_turn,
            entries,
            editing,
            resume,
            detached,
            recover: receipts
                .iter()
                .any(|receipt| receipt.phase != QueueSteerPhase::Detached),
        }))
    }
}

async fn read_queue(
    engine: &WorkspaceEngine,
    client: &AppServerClient,
    store: &AttachmentStore,
    thread: &ThreadId,
) -> Result<ChatRead<QueueSnapshot>, Failure> {
    let browser = CodexBrowser::new(client.clone());
    let chat = browser.thread_summary(thread, RPC_TIMEOUT).await?;
    let queue = browser.queue_snapshot(&chat, RPC_TIMEOUT).await?;
    engine
        .reconcile_queue_edit(client, store, thread, &queue)
        .await?;
    Ok(queue)
}

async fn apply_queue_work(
    engine: &WorkspaceEngine,
    client: &AppServerClient,
    store: &AttachmentStore,
    thread: &ThreadId,
    captured: Option<&ChatRead<QueueSnapshot>>,
    work: Work,
) -> Result<(), Failure> {
    if matches!(work, Work::Refresh) {
        return Ok(());
    }
    let captured = captured.ok_or("the queue has no captured read")?;
    let snapshot = captured.for_selection(client.identity(), thread)?;
    match work {
        Work::Refresh => {}
        Work::Advance => {
            engine
                .start_legacy_queue(client, store, thread, captured, None, RPC_TIMEOUT)
                .await?;
        }
        Work::FollowUp {
            intent,
            target,
            enabled,
        } => {
            if !enabled {
                engine
                    .steer_follow_up(intent, target, client, store, RPC_TIMEOUT)
                    .await?
                    .response?;
            } else if matches!(snapshot, QueueSnapshot::Unsupported) {
                engine
                    .enqueue_legacy_follow_up(client, store, target, captured, intent)
                    .await?;
            } else {
                engine
                    .enqueue_follow_up(intent, target, client, store, RPC_TIMEOUT)
                    .await?
                    .response?;
            }
        }
        Work::Command(command) => {
            apply_queue_command(engine, client, store, thread, captured, snapshot, command).await?;
        }
    }
    Ok(())
}

async fn apply_queue_command(
    engine: &WorkspaceEngine,
    client: &AppServerClient,
    store: &AttachmentStore,
    thread: &ThreadId,
    captured: &ChatRead<QueueSnapshot>,
    snapshot: &QueueSnapshot,
    command: QueueCommand,
) -> Result<(), Failure> {
    if let QueueSnapshot::Available(rows) = snapshot {
        let find = |id: &str| -> Result<&QueuedSubmission, Failure> {
            rows.iter()
                .find(|entry| entry.id == id)
                .ok_or_else(|| "the captured queue entry changed".into())
        };
        match command {
            QueueCommand::Edit(id) => {
                engine
                    .begin_queue_edit(client, store, thread, find(&id)?, RPC_TIMEOUT)
                    .await?;
            }
            QueueCommand::CancelEdit(id) => {
                engine
                    .cancel_queue_edit(
                        client,
                        store,
                        &find_edit(client, store, thread, &id)?,
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            QueueCommand::SaveEdit(id) => {
                engine
                    .save_queue_edit(
                        client,
                        store,
                        &find_edit(client, store, thread, &id)?,
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            QueueCommand::Delete(id) => {
                engine
                    .delete_queue_entry(client, store, thread, find(&id)?, RPC_TIMEOUT)
                    .await?;
            }
            QueueCommand::Resume(id) => {
                engine
                    .start_queue_entry(client, store, thread, find(&id)?, RPC_TIMEOUT)
                    .await?;
            }
            QueueCommand::Reorder(ids) => {
                engine
                    .reorder_queue(client, thread, captured, &ids, RPC_TIMEOUT)
                    .await?;
            }
            QueueCommand::Steer(target) => {
                let turn = ExecutionTarget {
                    thread: thread.clone(),
                    turn: TurnId(target.turn_id),
                };
                engine
                    .steer_server_queue_entry(
                        client,
                        store,
                        &turn,
                        find(&target.entry_id)?,
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            command => recover_queue(engine, client, store, thread, command).await?,
        }
    } else {
        match command {
            QueueCommand::Edit(id) => {
                engine
                    .edit_local_follow_up(client, store, thread, captured, parse_id(&id)?)
                    .await?;
            }
            QueueCommand::CancelEdit(id) => {
                engine
                    .cancel_local_follow_up_edit(
                        client,
                        store,
                        &find_edit(client, store, thread, &id)?,
                        captured,
                    )
                    .await?;
            }
            QueueCommand::SaveEdit(id) => {
                engine
                    .save_local_follow_up_edit(
                        client,
                        store,
                        &find_edit(client, store, thread, &id)?,
                        captured,
                    )
                    .await?;
            }
            QueueCommand::Delete(id) => {
                engine
                    .delete_local_follow_up(client, store, thread, captured, parse_id(&id)?)
                    .await?;
            }
            QueueCommand::Resume(id) => {
                engine
                    .start_legacy_queue(
                        client,
                        store,
                        thread,
                        captured,
                        Some(parse_id(&id)?),
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            QueueCommand::Reorder(ids) => {
                let ids = ids
                    .iter()
                    .map(|id| parse_id(id))
                    .collect::<Result<Vec<_>, _>>()?;
                engine
                    .reorder_local_follow_ups(client, store, thread, captured, &ids)
                    .await?;
            }
            QueueCommand::Steer(target) => {
                let turn = ExecutionTarget {
                    thread: thread.clone(),
                    turn: TurnId(target.turn_id),
                };
                engine
                    .steer_legacy_queue_entry(
                        client,
                        store,
                        &turn,
                        captured,
                        parse_id(&target.entry_id)?,
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            command => recover_queue(engine, client, store, thread, command).await?,
        }
    }
    Ok(())
}

async fn recover_queue(
    engine: &WorkspaceEngine,
    client: &AppServerClient,
    store: &AttachmentStore,
    thread: &ThreadId,
    command: QueueCommand,
) -> Result<(), Failure> {
    match command {
        QueueCommand::Recover => {
            engine
                .recover_queued_steering(client, store, thread, RPC_TIMEOUT)
                .await?;
        }
        QueueCommand::Restore(id) => {
            engine
                .restore_detached_steering(client, store, thread, parse_id(&id)?)
                .await?;
        }
        _ => return Err("the command has no captured queue entry".into()),
    }
    Ok(())
}

fn find_edit(
    client: &AppServerClient,
    store: &AttachmentStore,
    thread: &ThreadId,
    id: &str,
) -> Result<QueueEdit, Failure> {
    let checkout = client
        .identity()
        .workspace
        .checkout
        .as_ref()
        .ok_or("no checkout")?;
    store
        .queue_edit(checkout, thread)?
        .filter(|edit| edit.id.to_string() == id)
        .ok_or_else(|| "the captured queue edit changed".into())
}

fn parse_id(id: &str) -> Result<RequestId, uuid::Error> {
    Uuid::parse_str(id).map(RequestId)
}

fn queue_text(input: &[Value]) -> String {
    input
        .iter()
        .find_map(|item| item["text"].as_str())
        .unwrap_or("")
        .chars()
        .take(240)
        .collect()
}
