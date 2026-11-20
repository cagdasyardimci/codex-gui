use std::{collections::HashSet, time::Duration};

use codex_gui_core::{
    identity::{OperationIdentity, RequestId},
    ipc::{IpcError, QuitDecision, QuitView},
    workspace::{ExecutionSnapshot, ExecutionTarget, WorkspaceAction},
};
use tauri::{AppHandle, Manager};
use tokio::time::Instant;
use uuid::Uuid;

use crate::{fixture::Verification, quit_ipc::QuitLifecycle};

use super::{Failure, Navigation, report};

const QUIT_GRACE: Duration = Duration::from_secs(2);

pub(super) struct Quit {
    app: AppHandle,
    ticket: String,
    drain: Option<Drain>,
}

struct Drain {
    deadline: Instant,
    interrupts: HashSet<ExecutionTarget>,
}

impl Navigation {
    pub(super) fn begin_quit(&mut self, app: AppHandle) {
        if self.quit.is_some() {
            return;
        }
        let confirm = !self.inflight.is_empty()
            || self.queues.has_mutations()
            || self
                .backend
                .as_ref()
                .is_some_and(|backend| has_work(&backend.engine.snapshot().execution));
        let ticket = Uuid::new_v4().to_string();
        self.view.quit = Some(QuitView {
            ticket: ticket.clone(),
            confirm,
            draining: false,
        });
        self.quit = Some(Quit {
            app,
            ticket,
            drain: None,
        });
        self.publish_navigation();
    }

    pub(super) fn cancel_quit(&mut self, decision: QuitDecision) -> Result<(), IpcError> {
        self.authorize_quit(&decision)?;
        self.release_quit();
        Ok(())
    }

    pub(super) async fn confirm_quit(&mut self, decision: QuitDecision) -> Result<(), IpcError> {
        self.authorize_quit(&decision)?;
        if !self.failed_drafts.is_empty() {
            self.release_quit();
            return Err(IpcError::ProjectUnavailable);
        }
        if let Err(error) = self.owners.persist_retired() {
            self.release_quit();
            return Err(report(error.into()));
        }
        if let Some(backend) = &self.backend {
            let owner = backend.connection.client();
            for pending in self
                .inflight
                .values()
                .filter(|pending| &pending.operation.connection == owner.identity())
            {
                let _ = backend
                    .engine
                    .apply(WorkspaceAction::StopSubmission {
                        operation: pending.operation.clone(),
                    })
                    .await;
            }
        }
        let quit = self.quit.as_mut().expect("authorized quit");
        quit.drain = Some(Drain {
            deadline: Instant::now() + QUIT_GRACE,
            interrupts: HashSet::new(),
        });
        self.view.quit.as_mut().expect("published quit").draining = true;
        self.publish_navigation();
        Ok(())
    }

    fn authorize_quit(&self, decision: &QuitDecision) -> Result<(), IpcError> {
        if self
            .quit
            .as_ref()
            .is_none_or(|quit| quit.ticket != decision.ticket || quit.drain.is_some())
        {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }

    pub(super) fn draining_quit(&self) -> bool {
        self.quit.as_ref().is_some_and(|quit| quit.drain.is_some())
    }

    pub(super) async fn advance_quit(&mut self) -> bool {
        let Some(drain) = self.quit.as_mut().and_then(|quit| quit.drain.as_mut()) else {
            return false;
        };
        let execution = self
            .backend
            .as_ref()
            .map(|backend| backend.engine.snapshot());
        if let (Some(backend), Some(state)) = (&self.backend, &execution) {
            let client = backend.connection.client();
            for target in &state.execution.active_turns {
                if drain.interrupts.insert(target.clone()) {
                    let client = client.clone();
                    let target = target.clone();
                    let engine = backend.engine.clone();
                    let operation = OperationIdentity {
                        connection: client.identity().clone(),
                        request: RequestId(Uuid::new_v4()),
                    };
                    tauri::async_runtime::spawn(async move {
                        if let Err(error) = engine
                            .interrupt(operation, target, &client, QUIT_GRACE)
                            .await
                        {
                            eprintln!("{error}");
                        }
                    });
                }
            }
        }
        if Instant::now() < drain.deadline
            && (!self.inflight.is_empty()
                || self.queues.has_mutations()
                || execution
                    .as_ref()
                    .is_some_and(|state| has_work(&state.execution)))
        {
            return false;
        }
        if let Err(error) = self.persist_before_quit() {
            eprintln!("{error}");
            self.release_quit();
            return false;
        }
        let quit = self.quit.take().expect("confirmed quit is active");
        self.disconnect().await;
        quit.app.state::<QuitLifecycle>().allow_exit();
        if *quit.app.state::<Verification>() == Verification::Quit {
            println!(
                "Verified desktop quit drained drafts and retained unresolved execution evidence"
            );
        }
        quit.app.exit(0);
        true
    }

    fn persist_before_quit(&mut self) -> Result<(), Failure> {
        self.owners.persist_retired()?;
        if let Some(state) = self
            .backend
            .as_ref()
            .map(|backend| backend.engine.snapshot())
            && let Some(checkout) = &state.connection.workspace.checkout
        {
            self.store
                .preserve_exit_executions(checkout, &state.execution)?;
        }
        Ok(())
    }

    fn release_quit(&mut self) {
        self.quit = None;
        self.view.quit = None;
        self.sync_actions();
    }
}

fn has_work(execution: &ExecutionSnapshot) -> bool {
    !execution.active_turns.is_empty() || !execution.unresolved_commands.is_empty()
}
