use codex_gui_core::{
    codex::{BrowseError, ForkBoundary, RequestError, ThreadActivity, ThreadSummary},
    identity::TurnId,
    ipc::{ChatRequest, RecoverFork, TranscriptRowRequest},
    slash_commands::Command,
    storage::drafts::DraftRevision,
};

use super::{prompt_revision::ForkCompletion, *};

pub(super) struct ConversationForkCompletion {
    operation: Uuid,
    source: ChatRequest,
    rail: Uuid,
    checkout: CheckoutIdentity,
    connection: AppServerClient,
    boundary: ForkBoundary,
    draft: (DraftId, DraftRevision),
    command: Option<String>,
    result: Result<ThreadSummary, BrowseError>,
    _lease: RuntimeUse,
}

impl Navigation {
    pub(super) fn sync_fork_controls(&mut self) {
        let mut can_fork = false;
        let mut recover = false;
        if let Ok((selection, _, _)) = self.prompt_fork_scope()
            && let Some(source) = selection.thread.as_ref()
            && self
                .store
                .has_pending_fork_revision(&selection.checkout, source)
                .is_ok_and(|pending| !pending)
            && let Ok(receipt) = self
                .store
                .conversation_fork_receipt(&selection.checkout, source)
        {
            can_fork = receipt.is_none();
            recover = receipt
                .is_some_and(|operation| !self.prompt_revisions.active_forks.contains(&operation));
        }
        self.view.can_fork = can_fork;
        self.view.recover_fork = recover;
        if can_fork || recover {
            self.view.slash_commands.available.push(Command::Fork);
        }
        self.view.can_edit_sent_prompt = can_fork;
    }

    pub(super) async fn branch_response(
        &mut self,
        row: TranscriptRowRequest,
    ) -> Result<(), IpcError> {
        let (turn, _) = self.finished_response(&row)?;
        let source = ChatRequest {
            workspace_id: row.workspace_id,
            chat_id: row.chat_id,
        };
        self.start_conversation_fork(source, ForkBoundary::Through(TurnId(turn)), None)
            .await
    }

    pub(super) async fn start_conversation_fork(
        &mut self,
        source: ChatRequest,
        boundary: ForkBoundary,
        command: Option<String>,
    ) -> Result<(), IpcError> {
        self.require(source.workspace_id)?;
        self.sync_actions();
        if !self.view.can_fork {
            return Err(IpcError::StaleSelection);
        }
        let (selection, backend, rail) = self.prompt_fork_scope()?;
        let thread = selection
            .thread
            .as_ref()
            .filter(|thread| thread.0 == source.chat_id)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        let rail = rail.id;
        let checkout = selection.checkout.clone();
        let connection = backend.connection.client();
        let browser = CodexBrowser::new(connection.clone());
        let summary = browser
            .thread_summary(&thread, RPC_TIMEOUT)
            .await
            .map_err(|error| report(error.into()))?;
        let current = summary
            .for_selection(connection.identity(), &thread)
            .map_err(|error| report(error.into()))?;
        if !matches!(
            current.activity,
            ThreadActivity::Idle | ThreadActivity::NotLoaded
        ) {
            return Err(IpcError::StaleSelection);
        }
        let id = self.editor_id().ok_or(IpcError::StaleSelection)?;
        let revision = self
            .store
            .read_editor_draft(id)
            .map_err(|error| report(error.into()))?
            .revision;
        let lease = self
            .owners
            .acquire(connection.identity())
            .map_err(|error| report(error.into()))?;
        let operation = Uuid::new_v4();
        if !self
            .store
            .reserve_conversation_fork(&checkout, &thread, operation)
            .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        self.prompt_revisions.active_forks.insert(operation);
        let complete = self.prompt_revisions.sender.clone();
        tauri::async_runtime::spawn(async move {
            let result = browser.fork_chat(&summary, &boundary, RPC_TIMEOUT).await;
            let _ = complete
                .send(Box::new(ForkCompletion::Conversation(
                    ConversationForkCompletion {
                        operation,
                        source,
                        rail,
                        checkout,
                        connection,
                        boundary,
                        draft: (id, revision),
                        command,
                        result,
                        _lease: lease,
                    },
                )))
                .await;
        });
        self.sync_actions();
        Ok(())
    }

    pub(super) async fn complete_conversation_fork(
        &mut self,
        completion: ConversationForkCompletion,
    ) -> Result<(), Failure> {
        let ConversationForkCompletion {
            operation,
            source,
            rail,
            checkout,
            connection,
            boundary,
            draft,
            command,
            result,
            _lease,
        } = completion;
        self.prompt_revisions.active_forks.remove(&operation);
        let thread = ThreadId(source.chat_id);
        if self.store.conversation_fork_receipt(&checkout, &thread)? != Some(operation) {
            self.sync_actions();
            return Ok(());
        }
        let fork = match result {
            Ok(fork) => fork,
            Err(error) => {
                if matches!(&error, BrowseError::Request(error) if error.is_unsent() || matches!(error, RequestError::Remote(_)))
                {
                    self.store
                        .retire_conversation_fork(&checkout, &thread, operation)?;
                }
                self.sync_actions();
                return Err(error.into());
            }
        };
        self.store
            .retire_conversation_fork(&checkout, &thread, operation)?;
        let Some(selection) = self
            .selection
            .as_ref()
            .filter(|selection| selection.checkout == checkout)
        else {
            return Ok(());
        };
        let owns_selection = selection.id == source.workspace_id
            && selection.thread.as_ref() == Some(&thread)
            && self
                .view
                .turn_rail
                .as_ref()
                .is_some_and(|view| view.id == rail)
            && self.backend.as_ref().is_some_and(|backend| {
                backend.connection.client().identity() == connection.identity()
            })
            && self.quit.is_none()
            && self.view.actions.stop.is_none()
            && self.editor_id() == Some(draft.0)
            && self
                .store
                .read_editor_draft(draft.0)
                .is_ok_and(|saved| saved.revision == draft.1);
        let target = self.remember_fork(fork);
        self.sync_actions();
        if !owns_selection {
            return Ok(());
        }
        if let ForkBoundary::Through(turn) = boundary {
            let browser = CodexBrowser::new(connection.clone());
            let summary = browser.thread_summary(&target, RPC_TIMEOUT).await?;
            let page = browser.turn_statuses(&summary, None, RPC_TIMEOUT).await?;
            let head = page
                .for_selection(connection.identity(), &target)?
                .data
                .first();
            if head.is_none_or(|head| head.id != turn) {
                return Err("the fork did not end at the captured response turn".into());
            }
        }
        if let Some(command) = command {
            self.store
                .replace_editor_text(draft.0, Some(&command), String::new())?;
            self.set_editor(draft.0)?;
        }
        self.focus(Some(target)).await
    }

    pub(super) async fn recover_conversation_fork(
        &mut self,
        request: RecoverFork,
    ) -> Result<(), IpcError> {
        let RecoverFork { source, fork } = request;
        self.require(source.workspace_id)?;
        self.sync_actions();
        if !self.view.recover_fork {
            return Err(IpcError::StaleSelection);
        }
        let (selection, backend, _) = self.prompt_fork_scope()?;
        let thread = selection
            .thread
            .as_ref()
            .filter(|thread| thread.0 == source.chat_id)
            .cloned()
            .ok_or(IpcError::StaleSelection)?;
        let operation = self
            .store
            .conversation_fork_receipt(&selection.checkout, &thread)
            .map_err(|error| report(error.into()))?
            .ok_or(IpcError::StaleSelection)?;
        let fork = fork.map(ThreadId);
        if let Some(fork) = &fork {
            if fork == &thread {
                return Err(IpcError::StaleSelection);
            }
            CodexBrowser::new(backend.connection.client())
                .thread_summary(fork, RPC_TIMEOUT)
                .await
                .map_err(|error| report(error.into()))?;
        }
        self.store
            .retire_conversation_fork(&selection.checkout, &thread, operation)
            .map_err(|error| report(error.into()))?;
        self.sync_actions();
        if let Some(fork) = fork {
            self.focus(Some(fork)).await.map_err(report)?;
        }
        Ok(())
    }

    pub(super) fn remember_fork(&mut self, fork: ThreadSummary) -> ThreadId {
        self.view.chats.retain(|chat| chat.id != fork.id.0);
        self.view.chats.insert(
            0,
            ChatRow {
                id: fork.id.0.clone(),
                title: fork.name.unwrap_or_else(|| "Forked Chat".into()),
                preview: fork.preview,
            },
        );
        fork.id
    }
}
