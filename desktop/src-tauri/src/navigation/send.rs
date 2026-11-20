use std::sync::Arc;

use codex_gui_core::{
    identity::{OperationIdentity, RequestId, ThreadId, TurnId},
    ipc::{
        ChatRow, IpcError, SendRequest, StopTarget, TurnTarget, WriteAccess, present_question_reply,
    },
    storage::drafts::DraftId,
    workspace::{
        ExecutionTarget, SendDraft, SendIntent, SendSettings, SubmissionError, SubmissionReply,
        WorkspaceAction,
    },
};
use uuid::Uuid;

use super::{Failure, Navigation, RPC_TIMEOUT, report};

pub(super) struct InflightSend {
    pub operation: OperationIdentity,
    pub thread: ThreadId,
}

pub(super) struct SendCompletion {
    pub draft: DraftId,
    pub operation: OperationIdentity,
    pub result: Result<SubmissionReply, SubmissionError>,
}

impl Navigation {
    pub(super) async fn send_visible(&mut self, request: SendRequest) -> Result<(), IpcError> {
        self.require(request.workspace_id)?;
        self.sync_actions();
        if !self.view.actions.send
            || self.view.selected_chat != request.chat_id
            || self
                .view
                .draft
                .as_ref()
                .is_none_or(|draft| draft.id != request.draft_id)
        {
            return Err(IpcError::StaleSelection);
        }
        self.admit_send(request).await.map_err(report)
    }

    async fn admit_send(&mut self, request: SendRequest) -> Result<(), Failure> {
        let draft_id = DraftId(Uuid::parse_str(&request.draft_id)?);
        let saved = self.store.read_editor_draft(draft_id)?;
        if saved.text != request.text || saved.text.trim().is_empty() {
            return Err("the submitted text no longer matches the displayed draft".into());
        }
        let backend = self.backend.as_mut().ok_or("Codex is disconnected")?;
        let client = backend.connection.client();
        let engine = backend.engine.clone();
        let operation = OperationIdentity {
            connection: client.identity().clone(),
            request: RequestId(Uuid::new_v4()),
        };
        let intent = Arc::new(SendIntent {
            operation: operation.clone(),
            draft: SendDraft {
                id: draft_id,
                revision: saved.revision,
                text: saved.text,
                context: saved.context,
                attachments: Vec::new(),
            },
            settings: SendSettings::default(),
        });
        let prepared = match request.chat_id {
            Some(chat) => {
                engine
                    .reserve_thread_submission(intent, ThreadId(chat))
                    .await?
            }
            None => {
                engine
                    .apply(WorkspaceAction::AdmitFirstMessage(intent))
                    .await?;
                let effect = backend
                    .effects
                    .recv()
                    .await
                    .ok_or("the thread preparation queue closed")?;
                let prepared = engine
                    .prepare_thread(effect, &client, &self.store, RPC_TIMEOUT)
                    .await?;
                let thread = prepared.thread().clone();
                self.source_draft = self.store.desktop_selection()?.source_draft;
                let preview = present_question_reply(&request.text).into_owned();
                let title = preview
                    .lines()
                    .find(|line| !line.trim().is_empty())
                    .unwrap_or("New Chat")
                    .to_owned();
                self.view.chats.insert(
                    0,
                    ChatRow {
                        id: thread.0.clone(),
                        title,
                        preview,
                    },
                );
                self.adopt_focus(Some(thread))?;
                prepared
            }
        };
        let thread = prepared.thread().clone();
        self.inflight.insert(
            draft_id,
            InflightSend {
                operation: operation.clone(),
                thread,
            },
        );
        self.sync_actions();
        let store = self.store.clone();
        let completions = self.send_completions.clone();
        tauri::async_runtime::spawn(async move {
            let result = engine
                .submit_prepared(prepared, &client, &store, RPC_TIMEOUT)
                .await;
            let _ = completions
                .send(Box::new(SendCompletion {
                    draft: draft_id,
                    operation,
                    result,
                }))
                .await;
        });
        Ok(())
    }

    pub(super) fn complete_send(&mut self, completion: SendCompletion) {
        if self
            .inflight
            .get(&completion.draft)
            .is_none_or(|pending| pending.operation != completion.operation)
        {
            return;
        }
        self.inflight.remove(&completion.draft);
        match completion.result {
            Ok(reply) => {
                if let Err(error) = reply.response {
                    eprintln!("{error}");
                }
            }
            Err(error) => eprintln!("{error}"),
        }
        self.refresh_draft_after_submission(completion.draft);
    }

    pub(super) fn refresh_draft_after_submission(&mut self, draft: DraftId) {
        if self
            .view
            .draft
            .as_ref()
            .is_some_and(|value| value.id == draft.0.to_string())
        {
            if let Err(error) = self.set_editor(draft) {
                eprintln!("{error}");
            }
            self.refresh_recovery_action();
        }
        self.sync_actions();
    }

    pub(super) fn refresh_recovery_action(&mut self) {
        self.view.actions.recover = match (self.selection.as_ref(), self.editor_id()) {
            (Some(selection), Some(draft)) => self
                .store
                .has_unresolved_submission(&selection.checkout, draft)
                .unwrap_or_else(|error| {
                    eprintln!("{error}");
                    true
                }),
            _ => false,
        };
    }

    pub(super) async fn recover_send(&mut self) -> Result<(), Failure> {
        let backend = self.backend.as_ref().ok_or("Codex is disconnected")?;
        let client = backend.connection.client();
        let result = backend
            .engine
            .recover_submissions(&client, &self.store, RPC_TIMEOUT)
            .await?;
        for (_, error) in result.read_failures {
            eprintln!("{error}");
        }
        if let Some(draft) = self.editor_id() {
            self.refresh_draft_after_submission(draft);
        }
        Ok(())
    }

    pub(super) async fn stop(&mut self, target: StopTarget) -> Result<(), Failure> {
        if self.view.write_access != WriteAccess::Ready {
            return Err("writable operations are not available".into());
        }
        let backend = self.backend.as_ref().ok_or("Codex is disconnected")?;
        let client = backend.connection.client();
        match target {
            StopTarget::Turn(target) => {
                let operation = OperationIdentity {
                    connection: client.identity().clone(),
                    request: RequestId(Uuid::new_v4()),
                };
                backend
                    .engine
                    .interrupt(
                        operation,
                        ExecutionTarget {
                            thread: ThreadId(target.thread_id),
                            turn: TurnId(target.turn_id),
                        },
                        &client,
                        RPC_TIMEOUT,
                    )
                    .await?;
            }
            StopTarget::Submission(target) => {
                let request = RequestId(Uuid::parse_str(&target)?);
                let pending = self
                    .inflight
                    .values()
                    .find(|pending| pending.operation.request == request)
                    .filter(|pending| &pending.operation.connection == client.identity())
                    .ok_or("the submission no longer owns a pending send")?;
                backend
                    .engine
                    .apply(WorkspaceAction::StopSubmission {
                        operation: pending.operation.clone(),
                    })
                    .await?;
            }
        }
        self.sync_actions();
        Ok(())
    }

    pub(super) fn sync_actions(&mut self) {
        self.view.actions.send = false;
        self.view.actions.stop = None;
        self.view.actions.interactions.clear();
        let Some(backend) = &self.backend else {
            self.publish_navigation();
            return;
        };
        let state = backend.engine.snapshot();
        if self.view.write_access == WriteAccess::Ready {
            let selected = self
                .selection
                .as_ref()
                .and_then(|selection| selection.thread.as_ref());
            let inflight = self
                .inflight
                .values()
                .filter(|send| send.operation.connection == state.connection);
            let active = state
                .execution
                .active_turns
                .iter()
                .find(|turn| Some(&turn.thread) == selected)
                .or_else(|| state.execution.active_turns.first());
            let pending = inflight
                .clone()
                .find(|send| Some(&send.thread) == selected)
                .or_else(|| inflight.clone().min_by_key(|send| send.operation.request.0));
            self.view.actions.stop = active
                .map(|turn| {
                    StopTarget::Turn(TurnTarget {
                        thread_id: turn.thread.0.clone(),
                        turn_id: turn.turn.0.clone(),
                    })
                })
                .or_else(|| {
                    pending.map(|send| StopTarget::Submission(send.operation.request.0.to_string()))
                });
            self.view.actions.send = self.view.account.permits_turns
                && self.editor_id().is_some()
                && !self.view.actions.recover
                && selected.is_none_or(|thread| {
                    state.writable_threads.contains(thread)
                        && !state
                            .execution
                            .active_turns
                            .iter()
                            .any(|turn| &turn.thread == thread)
                })
                && !inflight
                    .clone()
                    .any(|send| selected.is_none_or(|thread| thread == &send.thread));
            self.view.actions.interactions = self
                .interactions
                .project(backend.engine.pending_interactions(), selected);
        }
        self.publish_navigation();
    }

    pub(super) fn editor_id(&self) -> Option<DraftId> {
        self.view
            .draft
            .as_ref()
            .and_then(|draft| Uuid::parse_str(&draft.id).ok())
            .map(DraftId)
    }
}
