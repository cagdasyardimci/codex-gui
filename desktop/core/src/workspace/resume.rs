use std::{collections::HashSet, path::PathBuf, sync::Arc, time::Duration};

use serde::Deserialize;
use serde_json::json;
use thiserror::Error;
use tokio::sync::{mpsc, watch};

use super::{
    InteractionError, PendingInteraction, SubmissionError, WorkspaceAction, WorkspaceEngine,
    WorkspaceError,
};
use crate::{
    checkout::CheckoutError,
    codex::{
        AppServerClient, AppServerConnection, BrowseError, ChatRead, ChatSummary, CodexBrowser,
        QueueSnapshot, RequestError, ServerEvent, ThreadSummary, TurnStatus,
    },
    identity::{ConnectionIdentity, ThreadId},
    storage::attachments::AttachmentStore,
};

const MAX_EARLY_EVENTS: usize = 128;
const MAX_RESUME_HISTORY_PAGES: usize = 25;

#[derive(Debug, Error)]
pub enum ResumeError {
    #[error(transparent)]
    Workspace(#[from] WorkspaceError),
    #[error(transparent)]
    Browse(#[from] BrowseError),
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Interaction(#[from] InteractionError),
    #[error(transparent)]
    Submission(#[from] SubmissionError),
    #[error("invalid thread/resume reply: {0}")]
    Response(#[from] serde_json::Error),
    #[error("app-server event stream ended during resume")]
    EventStreamClosed,
    #[error("app-server exceeded the early resume event limit")]
    TooManyEarlyEvents,
}

#[derive(Debug)]
pub struct ResumedChat {
    pub summary: ChatRead<ChatSummary>,
    pub mode: ResumedMode,
    pub events: Vec<RoutedEvent>,
}

#[derive(Debug)]
pub enum ResumedMode {
    Writable {
        queue: Result<ChatRead<QueueSnapshot>, BrowseError>,
        execution: Result<(), Box<ResumeError>>,
    },
    ReadOnly,
}

#[derive(Debug)]
pub enum RoutedEvent {
    Interaction(Arc<PendingInteraction>),
    QueueChanged(ThreadId),
    Conversation {
        thread: ThreadId,
        event: ServerEvent,
    },
}

#[derive(Deserialize)]
struct ResumedLocation {
    thread: ThreadSummary,
    cwd: PathBuf,
}

impl WorkspaceEngine {
    pub async fn resume_thread(
        &self,
        connection: &mut AppServerConnection,
        store: &AttachmentStore,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<ResumedChat, ResumeError> {
        let client = connection.client();
        self.resume_with_events(&client, connection.event_receiver(), store, thread, timeout)
            .await
    }

    pub(crate) async fn resume_with_events(
        &self,
        client: &AppServerClient,
        incoming: &mut mpsc::Receiver<ServerEvent>,
        store: &AttachmentStore,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<ResumedChat, ResumeError> {
        let owner = client.identity();
        self.check_owner(owner)?;
        let browser = CodexBrowser::new(client.clone());
        let summary = browser.thread_summary(thread, timeout).await?;
        let checkout = owner
            .workspace
            .checkout
            .clone()
            .ok_or(WorkspaceError::MissingCheckout)?;
        let (stop, stopped) = watch::channel(false);
        self.apply(WorkspaceAction::ReserveResume {
            owner: owner.clone(),
            thread: thread.clone(),
            stopped: stop,
        })
        .await?;

        let reply = client.request_scoped(
            "thread/resume",
            json!({"threadId": thread.0, "excludeTurns": true}),
            timeout,
            checkout.clone(),
            stopped,
        );
        tokio::pin!(reply);
        let mut early = Vec::new();
        let mut events = Vec::new();
        let reply = loop {
            tokio::select! {
                biased;
                reply = &mut reply => break reply,
                incoming = incoming.recv() => {
                    let event = incoming.ok_or(ResumeError::EventStreamClosed)?;
                    if thread_of(&event) == Some(thread.0.as_str()) {
                        if early.len() == MAX_EARLY_EVENTS {
                            return Err(ResumeError::TooManyEarlyEvents);
                        }
                        early.push(event);
                    } else if let Some(event) = self.route_session_event(client, store, event, timeout).await? {
                        events.push(event);
                    }
                }
            }
        };
        let reply = match reply {
            Ok(reply) => reply,
            Err(error) => {
                if error.is_unsent() || matches!(error, RequestError::Remote(_)) {
                    self.finish_resume(owner, thread, false).await?;
                }
                if competing_writer(&error) {
                    checkout.revalidate()?;
                    return Ok(ResumedChat {
                        summary,
                        mode: ResumedMode::ReadOnly,
                        events,
                    });
                }
                return Err(error.into());
            }
        };
        let resumed: ResumedLocation = serde_json::from_value(reply)?;
        if &resumed.thread.id != thread {
            return Err(BrowseError::WrongThread.into());
        }
        checkout.validate_reported(&resumed.cwd)?;
        checkout.validate_reported(&resumed.thread.cwd)?;
        self.finish_resume(owner, thread, true).await?;
        for event in early.drain(..) {
            if let Some(event) = self
                .route_session_event(client, store, event, timeout)
                .await?
            {
                events.push(event);
            }
        }

        let read = async {
            let queue = browser.queue_snapshot(&summary, timeout).await;
            let execution = self
                .reconcile_resumed_execution(&browser, &summary, owner, thread, timeout)
                .await;
            (queue, execution)
        };
        let (queue, execution) = {
            tokio::pin!(read);
            loop {
                tokio::select! {
                    biased;
                    result = &mut read => break result,
                    incoming = incoming.recv() => {
                        let event = incoming.ok_or(ResumeError::EventStreamClosed)?;
                        if early.len() == MAX_EARLY_EVENTS {
                            return Err(ResumeError::TooManyEarlyEvents);
                        }
                        early.push(event);
                    }
                }
            }
        };
        for event in early {
            if let Some(event) = self
                .route_session_event(client, store, event, timeout)
                .await?
            {
                events.push(event);
            }
        }
        self.check_owner(owner)?;
        Ok(ResumedChat {
            summary,
            mode: ResumedMode::Writable {
                queue,
                execution: execution.map_err(Box::new),
            },
            events,
        })
    }

    pub async fn route_session_event(
        &self,
        client: &AppServerClient,
        store: &AttachmentStore,
        event: ServerEvent,
        timeout: Duration,
    ) -> Result<Option<RoutedEvent>, ResumeError> {
        let owner = client.identity();
        self.check_owner(owner)?;
        let thread = thread_of(&event).map(|id| ThreadId(id.to_owned()));
        if let Some(thread) = &thread
            && !self.snapshot().writable_threads.contains(thread)
        {
            return Ok(None);
        }
        if let ServerEvent::Notification { method, .. } = &event
            && method == "thread/queue/changed"
        {
            return Ok(thread.map(RoutedEvent::QueueChanged));
        }
        self.observe_submission_event(owner, &event, store).await?;
        self.observe_execution_event(owner, &event).await?;
        if let Some(thread) = thread
            && matches!(&event, ServerEvent::Notification { method, params }
                if matches!(method.as_str(), "turn/completed" | "item/agentMessage/delta")
                   || (method == "item/completed"
                       && matches!(params["item"]["type"].as_str(), Some("agentMessage" | "userMessage"))))
        {
            return Ok(Some(RoutedEvent::Conversation { thread, event }));
        }
        Ok(self
            .receive_interaction(client, event, timeout)
            .await?
            .map(RoutedEvent::Interaction))
    }

    fn check_owner(&self, owner: &ConnectionIdentity) -> Result<(), WorkspaceError> {
        if &self.snapshot().connection != owner {
            return Err(WorkspaceError::Retired);
        }
        Ok(())
    }

    async fn finish_resume(
        &self,
        owner: &ConnectionIdentity,
        thread: &ThreadId,
        writable: bool,
    ) -> Result<(), WorkspaceError> {
        self.apply(WorkspaceAction::FinishResume {
            owner: owner.clone(),
            thread: thread.clone(),
            writable,
        })
        .await?;
        Ok(())
    }

    async fn reconcile_resumed_execution(
        &self,
        browser: &CodexBrowser,
        summary: &ChatRead<ChatSummary>,
        owner: &ConnectionIdentity,
        thread: &ThreadId,
        timeout: Duration,
    ) -> Result<(), ResumeError> {
        let statuses = browser.turn_statuses(summary, None, timeout).await?;
        let statuses = statuses.for_selection(owner, thread)?;
        for turn in &statuses.data {
            self.reconcile_turn_activity(owner, thread, turn).await?;
        }
        let mut needed: HashSet<_> = statuses
            .data
            .iter()
            .filter(|turn| turn.status == TurnStatus::InProgress)
            .map(|turn| turn.id.clone())
            .collect();
        needed.extend(
            self.snapshot()
                .execution
                .unresolved_commands
                .iter()
                .filter(|command| &command.target.thread == thread)
                .map(|command| command.target.turn.clone()),
        );
        let mut cursor = None;
        for _ in 0..MAX_RESUME_HISTORY_PAGES {
            if needed.is_empty() {
                break;
            }
            let page = browser
                .history(summary, cursor.as_ref(), timeout)
                .await?
                .into_for_selection(owner, thread)?;
            for turn in &page.data {
                if needed.remove(&turn.activity.id) {
                    self.reconcile_history_turn(owner, thread, turn).await?;
                }
            }
            cursor = page.next_cursor;
            if cursor.is_none() {
                break;
            }
        }
        Ok(())
    }
}

fn thread_of(event: &ServerEvent) -> Option<&str> {
    let params = match event {
        ServerEvent::Request { params, .. } | ServerEvent::Notification { params, .. } => params,
    };
    params["threadId"].as_str()
}

fn competing_writer(error: &RequestError) -> bool {
    let RequestError::Remote(error) = error else {
        return false;
    };
    let message = error.message.to_ascii_lowercase();
    message.contains("already has an active writer")
        || ([
            "another app",
            "another client",
            "another instance",
            "another process",
        ]
        .iter()
        .any(|label| message.contains(label))
            && ["open", "active", "in use", "owned", "locked"]
                .iter()
                .any(|label| message.contains(label)))
}
