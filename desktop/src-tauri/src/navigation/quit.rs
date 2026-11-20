use std::{collections::HashSet, sync::atomic::Ordering, time::Duration};

use codex_gui_core::{
    identity::{ConnectionIdentity, OperationIdentity, RequestId},
    ipc::{FileQuitAction, IpcError, QuitDecision, QuitView},
    workspace::{ExecutionSnapshot, ExecutionTarget, WorkspaceAction},
};
use tauri::{AppHandle, Manager};
use tokio::time::Instant;
use uuid::Uuid;

use crate::{fixture::Verification, quit_ipc::QuitLifecycle};

use super::{Failure, Navigation, file_tools::CapturedFileDiscard, report};

const QUIT_GRACE: Duration = Duration::from_secs(2);

pub(super) struct Quit {
    action: Shutdown,
    ticket: String,
    drain: Option<Drain>,
    discard_files: Option<Vec<CapturedFileDiscard>>,
}

enum Shutdown {
    Quit(AppHandle),
    StopAll,
}

struct Drain {
    deadline: Instant,
    interrupts: HashSet<(ConnectionIdentity, ExecutionTarget)>,
}

impl Navigation {
    pub(super) fn begin_quit(&mut self, app: AppHandle) {
        self.begin_shutdown(Shutdown::Quit(app));
    }

    pub(super) fn begin_stop_all(&mut self) {
        if self.has_stoppable_work() {
            self.begin_shutdown(Shutdown::StopAll);
        }
    }

    pub(super) fn has_stoppable_work(&self) -> bool {
        !self.inflight.is_empty()
            || self
                .runtime_connections()
                .any(|(_, engine)| !engine.snapshot().execution.active_turns.is_empty())
    }

    fn begin_shutdown(&mut self, action: Shutdown) {
        if self.quit.is_some() {
            return;
        }
        self.retire_file_search();
        let stop_only = matches!(action, Shutdown::StopAll);
        let dirty_files = !stop_only && self.file_tools.has_edits(None);
        let confirm = dirty_files
            || !self.inflight.is_empty()
            || self.queues.has_mutations()
            || self
                .runtime_connections()
                .any(|(_, engine)| has_work(&engine.snapshot().execution));
        let ticket = Uuid::new_v4().to_string();
        self.shutdown_pending.store(true, Ordering::SeqCst);
        self.view.quit = Some(QuitView {
            ticket: ticket.clone(),
            confirm,
            draining: false,
            stop_only,
            file_action: dirty_files.then_some(FileQuitAction::Save),
        });
        self.quit = Some(Quit {
            action,
            ticket,
            drain: None,
            discard_files: None,
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
        let quit = self.quit.as_mut().expect("authorized quit");
        if !matches!(quit.action, Shutdown::StopAll) {
            let files_settled = if let Some(discard) = quit.discard_files.take() {
                self.file_tools.discard_all(&discard)
            } else {
                let failures = self.file_tools.save_all(&self.owners);
                if failures.is_empty() {
                    true
                } else {
                    quit.discard_files = Some(failures);
                    false
                }
            };
            if !files_settled {
                let next_ticket = Uuid::new_v4().to_string();
                quit.ticket.clone_from(&next_ticket);
                let view = self.view.quit.as_mut().expect("published quit");
                view.ticket = next_ticket;
                view.confirm = true;
                view.file_action = Some(if quit.discard_files.is_some() {
                    FileQuitAction::Discard
                } else {
                    FileQuitAction::Save
                });
                self.publish_navigation();
                return Ok(());
            }
        }
        for (client, engine) in self.runtime_connections() {
            for pending in self
                .inflight
                .values()
                .filter(|pending| &pending.operation.connection == client.identity())
            {
                let _ = engine
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
        if !self.draining_quit() {
            return false;
        }
        let runtimes: Vec<_> = self.runtime_connections().collect();
        let Some(drain) = self.quit.as_mut().and_then(|quit| quit.drain.as_mut()) else {
            return false;
        };
        let mut remote_work = false;
        for (client, engine) in runtimes {
            let state = engine.snapshot();
            remote_work |= has_work(&state.execution);
            for target in &state.execution.active_turns {
                if drain
                    .interrupts
                    .insert((state.connection.clone(), target.clone()))
                {
                    let client = client.clone();
                    let target = target.clone();
                    let engine = engine.clone();
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
        if !self.inflight.is_empty()
            || self.queues.has_mutations()
            || self.owners.has_local_work(None)
            || (Instant::now() < drain.deadline && remote_work)
        {
            return false;
        }
        if let Err(error) = self.persist_before_quit() {
            eprintln!("{error}");
            self.release_quit();
            return false;
        }
        let quit = self.quit.take().expect("confirmed quit is active");
        let Shutdown::Quit(app) = quit.action else {
            self.release_quit();
            return false;
        };
        self.disconnect().await;
        self.stop_parked().await;
        app.state::<QuitLifecycle>().allow_exit();
        if *app.state::<Verification>() == Verification::Quit {
            println!(
                "Verified desktop quit drained drafts and retained unresolved execution evidence"
            );
        }
        if *app.state::<Verification>() == Verification::FileTools {
            println!("Verified installed file tools and hidden-tab quit settlement");
        }
        app.exit(0);
        true
    }

    fn persist_before_quit(&mut self) -> Result<(), Failure> {
        self.owners.persist_retired()?;
        self.owners.persist_running()?;
        Ok(())
    }

    fn release_quit(&mut self) {
        self.quit = None;
        self.view.quit = None;
        self.shutdown_pending.store(false, Ordering::SeqCst);
        self.sync_actions();
    }
}

fn has_work(execution: &ExecutionSnapshot) -> bool {
    !execution.active_turns.is_empty() || !execution.unresolved_commands.is_empty()
}
