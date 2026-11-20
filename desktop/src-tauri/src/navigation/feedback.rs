use codex_gui_core::{
    codex::RequestError,
    ipc::{FeedbackRequest, FeedbackView},
};
use serde_json::{Value, json};

use super::*;

pub(super) struct Feedback {
    pending: bool,
    disabled: Option<ConnectionIdentity>,
    sender: mpsc::Sender<Box<FeedbackOutcome>>,
    pub(super) completed: mpsc::Receiver<Box<FeedbackOutcome>>,
}

pub(super) struct FeedbackOutcome {
    checkout: CheckoutIdentity,
    owner: ConnectionIdentity,
    thread: ThreadId,
    turn: String,
    result: Result<Value, RequestError>,
}

impl Default for Feedback {
    fn default() -> Self {
        let (sender, completed) = mpsc::channel(1);
        Self {
            pending: false,
            disabled: None,
            sender,
            completed,
        }
    }
}

impl Navigation {
    pub(super) fn reload_feedback(&mut self) -> Result<(), Failure> {
        let mut view = FeedbackView::default();
        if let Some(selection) = &self.selection
            && let Some(thread) = &selection.thread
        {
            view.blocked_turns = self.store.reserved_feedback(&selection.checkout, thread)?;
            view.available = self.quit.is_none()
                && !self.feedback.pending
                && self.backend.as_ref().is_some_and(|backend| {
                    let client = backend.connection.client();
                    self.feedback.disabled.as_ref() != Some(client.identity())
                });
        }
        self.view.feedback = view;
        Ok(())
    }

    pub(super) async fn submit_feedback(
        &mut self,
        request: FeedbackRequest,
    ) -> Result<(), IpcError> {
        self.require(request.row.workspace_id)?;
        if !self.view.feedback.available || self.feedback.pending || self.quit.is_some() {
            return Err(IpcError::StaleSelection);
        }
        let (turn, _) = self
            .model
            .lock()
            .expect("workspace state lock poisoned")
            .projection
            .finished_response(&request.row)?;
        if !self.view.turn_rail.as_ref().is_some_and(|rail| {
            rail.turns
                .iter()
                .any(|item| item.id == turn && item.finished)
        }) || self.view.feedback.blocked_turns.contains(&turn)
        {
            return Err(IpcError::StaleSelection);
        }
        let checkout = self
            .selection
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .checkout
            .clone();
        let thread = ThreadId(request.row.chat_id);
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .connection
            .client();
        let owner = client.identity().clone();
        let cwd = checkout
            .canonical_path()
            .to_str()
            .ok_or(IpcError::InvalidCheckout)?;
        let value = client
            .request(
                "config/read",
                json!({"includeLayers": false, "cwd": cwd}),
                RPC_TIMEOUT,
            )
            .await
            .map_err(|error| report(error.into()))?;
        if !feedback_enabled(&value)? {
            self.feedback.disabled = Some(owner);
            self.reload_feedback().map_err(report)?;
            self.publish_navigation();
            return Err(IpcError::StaleSelection);
        }
        checkout
            .revalidate()
            .map_err(|_| IpcError::RetiredWorkspace)?;
        let lease = self
            .owners
            .acquire(&owner)
            .map_err(|error| report(error.into()))?;
        if !self
            .store
            .reserve_feedback(&checkout, &thread, &turn)
            .map_err(|error| report(error.into()))?
        {
            return Err(IpcError::StaleSelection);
        }
        self.feedback.pending = true;
        self.view.feedback.available = false;
        self.view.feedback.blocked_turns.push(turn.clone());
        self.publish_navigation();
        let complete = self.feedback.sender.clone();
        tauri::async_runtime::spawn(async move {
            let result = client
                .request(
                    "feedback/upload",
                    json!({
                        "classification": request.rating,
                        "threadId": thread.0,
                        "includeLogs": false,
                        "tags": {"turn_id": turn},
                    }),
                    RPC_TIMEOUT,
                )
                .await;
            let _ = complete
                .send(Box::new(FeedbackOutcome {
                    checkout,
                    owner,
                    thread,
                    turn,
                    result,
                }))
                .await;
            drop(lease);
        });
        Ok(())
    }

    pub(super) fn complete_feedback(&mut self, outcome: FeedbackOutcome) {
        self.feedback.pending = false;
        let saved = match outcome.result {
            Ok(response)
                if response["threadId"]
                    .as_str()
                    .is_some_and(|id| !id.is_empty()) =>
            {
                self.store
                    .confirm_feedback(&outcome.checkout, &outcome.thread, &outcome.turn)
            }
            Ok(_) => Ok(()),
            Err(error) => {
                let disabled = unsupported_feedback(&error);
                if disabled {
                    self.feedback.disabled = Some(outcome.owner);
                }
                if disabled || error.is_unsent() {
                    self.store
                        .release_feedback(&outcome.checkout, &outcome.thread, &outcome.turn)
                } else {
                    Ok(())
                }
            }
        };
        if let Err(error) = saved {
            eprintln!("{error}");
        }
        if let Err(error) = self.reload_feedback() {
            eprintln!("{error}");
        }
        self.publish_navigation();
    }
}

fn feedback_enabled(value: &Value) -> Result<bool, IpcError> {
    let config = value["config"]
        .as_object()
        .ok_or(IpcError::ProjectUnavailable)?;
    match config.get("feedback").filter(|value| !value.is_null()) {
        None => Ok(true),
        Some(feedback) => match feedback
            .as_object()
            .ok_or(IpcError::ProjectUnavailable)?
            .get("enabled")
            .filter(|enabled| !enabled.is_null())
        {
            None => Ok(true),
            Some(enabled) => enabled.as_bool().ok_or(IpcError::ProjectUnavailable),
        },
    }
}

fn unsupported_feedback(error: &RequestError) -> bool {
    let RequestError::Remote(error) = error else {
        return false;
    };
    let message = error.message.to_ascii_lowercase();
    error.code == -32601
        || [
            "feedback is disabled",
            "does not support result feedback",
            "method not found",
            "unknown method",
        ]
        .iter()
        .any(|text| message.contains(text))
}
