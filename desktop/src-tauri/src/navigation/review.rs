use codex_gui_core::{
    codex::{
        CliQualification, RequestError, ReviewDelivery, ReviewError, ReviewStarted, ReviewTarget,
    },
    ipc::{ChatRow, StartReviewRequest},
    slash_commands::{Command, ComposerInput, parse},
    storage::attachments::review_runs::ReviewReservation,
};
use uuid::Uuid;

use super::*;

pub(super) struct Reviews {
    pending: HashSet<(CheckoutIdentity, ThreadId)>,
    sender: mpsc::Sender<Box<ReviewOutcome>>,
    pub(super) completed: mpsc::Receiver<Box<ReviewOutcome>>,
}

pub(super) struct ReviewOutcome {
    checkout: CheckoutIdentity,
    owner: ConnectionIdentity,
    source: ThreadId,
    reservation: ReviewReservation,
    result: Result<ReviewStarted, ReviewError>,
    chat: Option<(ChatRow, i64)>,
}

impl Default for Reviews {
    fn default() -> Self {
        let (sender, completed) = mpsc::channel(16);
        Self {
            pending: HashSet::new(),
            sender,
            completed,
        }
    }
}

impl Navigation {
    pub(super) fn review_pending(&self, checkout: &CheckoutIdentity, source: &ThreadId) -> bool {
        self.reviews
            .pending
            .contains(&(checkout.clone(), source.clone()))
    }

    pub(super) fn review_available(&self, backend: &Backend, selection: &Selection) -> bool {
        let Some(source) = &selection.thread else {
            return false;
        };
        let runtime = backend.engine.snapshot();
        self.view.actions.send
            && backend.connection.compatibility().qualification() != CliQualification::Unverified
            && !runtime
                .execution
                .active_turns
                .iter()
                .any(|turn| &turn.thread == source)
            && !self.review_pending(&selection.checkout, source)
            && self
                .store
                .has_review_reservation(&selection.checkout, source)
                .is_ok_and(|reserved| !reserved)
    }

    pub(super) fn start_review(&mut self, request: StartReviewRequest) -> Result<(), IpcError> {
        let draft = request.draft;
        self.require(draft.workspace_id)?;
        self.validate_send_selection(&draft)?;
        self.sync_actions();
        let selection = self.selection.as_ref().ok_or(IpcError::RetiredWorkspace)?;
        let backend = self.backend.as_ref().ok_or(IpcError::StaleSelection)?;
        if !self.review_available(backend, selection) || self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let ComposerInput::Command {
            command: Command::Review,
            arguments,
        } = parse(&draft.text)
        else {
            return Err(IpcError::StaleSelection);
        };
        let argument = arguments.trim();
        if !request.target.valid()
            || (!argument.is_empty()
                && ReviewTarget::from_argument(argument).as_ref() != Some(&request.target))
        {
            return Err(IpcError::StaleSelection);
        }
        let draft_id = self.editor_id().ok_or(IpcError::StaleSelection)?;
        let saved = self
            .store
            .read_editor_draft(draft_id)
            .map_err(|error| report(error.into()))?;
        if saved.text != draft.text
            || super::composer_attachments::views(&saved.context)
                .iter()
                .map(|entry| &entry.id)
                .ne(draft.attachment_ids.iter())
        {
            return Err(IpcError::StaleSelection);
        }
        let checkout = selection.checkout.clone();
        let source = selection.thread.clone().ok_or(IpcError::StaleSelection)?;
        let client = backend.connection.client();
        let engine = backend.engine.clone();
        let owners = self.owners.clone();
        let lease = owners
            .acquire(client.identity())
            .map_err(|error| report(error.into()))?;
        let reservation = ReviewReservation {
            request: Uuid::new_v4(),
            draft: draft_id,
            revision: saved.revision,
        };
        if !self
            .store
            .reserve_review(&checkout, &source, reservation.request)
            .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        self.reviews
            .pending
            .insert((checkout.clone(), source.clone()));
        let done = self.reviews.sender.clone();
        let delivery = request.delivery;
        self.sync_actions();
        tauri::async_runtime::spawn(async move {
            let result = client
                .start_review(&source, &request.target, delivery, RPC_TIMEOUT)
                .await;
            let chat = match &result {
                Ok(started) => {
                    match track_review(&client, &engine, &owners, started, delivery).await {
                        Ok(chat) => chat,
                        Err(error) => {
                            eprintln!("{error}");
                            None
                        }
                    }
                }
                Err(_) => None,
            };
            let _ = done
                .send(Box::new(ReviewOutcome {
                    checkout,
                    owner: client.identity().clone(),
                    source,
                    reservation,
                    result,
                    chat,
                }))
                .await;
            drop(lease);
        });
        Ok(())
    }

    pub(super) fn complete_review(&mut self, outcome: ReviewOutcome) -> Result<(), Failure> {
        self.reviews
            .pending
            .remove(&(outcome.checkout.clone(), outcome.source.clone()));
        let accepted = match &outcome.result {
            Ok(started) => {
                self.present_finished_review(&outcome.owner, started);
                Some(true)
            }
            Err(ReviewError::Request(error))
                if error.is_unsent() || matches!(error, RequestError::Remote(_)) =>
            {
                Some(false)
            }
            Err(ReviewError::MissingCheckout | ReviewError::InvalidTarget) => Some(false),
            Err(error) => {
                eprintln!("{error}");
                None
            }
        };
        if let Some(accepted) = accepted
            && self.store.settle_review(
                &outcome.checkout,
                &outcome.source,
                outcome.reservation,
                accepted,
            )?
            && self.editor_id() == Some(outcome.reservation.draft)
        {
            self.set_editor(outcome.reservation.draft)?;
        }
        if let Some((chat, updated_at)) = outcome.chat
            && !self.deleted_chats.contains(&ThreadId(chat.id.clone()))
        {
            self.store
                .remember_sidebar_chats(&outcome.checkout, [(chat.clone(), updated_at)])?;
            if self
                .selection
                .as_ref()
                .is_some_and(|scope| scope.checkout == outcome.checkout)
                && !self.view.chats.iter().any(|row| row.id == chat.id)
            {
                self.view.chats.push(chat);
            }
            self.reload_sidebar()?;
        }
        self.sync_actions();
        Ok(())
    }

    fn present_finished_review(&mut self, owner: &ConnectionIdentity, started: &ReviewStarted) {
        let activity = &started.turn.activity;
        if !activity.status.is_finished()
            || self
                .backend
                .as_ref()
                .is_none_or(|backend| &backend.engine.snapshot().connection != owner)
        {
            return;
        }
        let Some(selection) = self
            .selection
            .as_ref()
            .filter(|selection| selection.thread.as_ref() == Some(&started.review_thread_id))
        else {
            return;
        };
        let checkout = selection.checkout.clone();
        let workspace = selection.id;
        self.observe_rail_turn(&started.review_thread_id, &activity.id.0, activity.status);
        self.flush_stream();
        for wire in &started.turn.items {
            if let Some(item) = message_item(&checkout, &activity.id.0, wire, true) {
                self.publish_stream(workspace, StreamChange::FinalItem(item));
            }
        }
    }
}

async fn track_review(
    client: &AppServerClient,
    engine: &WorkspaceEngine,
    owners: &RuntimeOwners,
    review: &ReviewStarted,
    delivery: ReviewDelivery,
) -> Result<Option<(ChatRow, i64)>, Failure> {
    let before = engine.snapshot();
    let owner = client.identity();
    let thread = &review.review_thread_id;
    let browser = CodexBrowser::new(client.clone());
    let summary = browser.thread_summary(thread, RPC_TIMEOUT).await?;
    let metadata = summary.for_selection(owner, thread)?;
    if delivery == ReviewDelivery::Detached {
        engine.admit_review_thread(owner, thread).await?;
    }
    let observed = if review.turn.activity.status == TurnStatus::InProgress {
        browser
            .turn_statuses(&summary, None, RPC_TIMEOUT)
            .await
            .ok()
    } else {
        None
    };
    let activity = observed
        .as_ref()
        .and_then(|page| page.for_selection(owner, thread).ok())
        .and_then(|page| {
            page.data
                .iter()
                .find(|turn| turn.id == review.turn.activity.id)
        })
        .unwrap_or(&review.turn.activity);
    engine
        .observe_review_activity(owner, thread, activity)
        .await?;
    if before.execution != engine.snapshot().execution {
        owners.record_execution(owner, &before.execution)?;
    }
    Ok((delivery == ReviewDelivery::Detached)
        .then(|| sidebar::sidebar_chat_row(metadata.thread.clone())))
}
