use std::sync::atomic::Ordering;
use tauri::Manager;

use codex_gui_core::{
    codex::{AppServerClient, QueueSnapshot, ServerEvent, StderrTail},
    ipc::SidebarChatKey,
    storage::attachments::LegacyQueueStatus,
    workspace::{RoutedEvent, RuntimeOwners, WorkspaceEngine},
};
use tokio::{sync::oneshot, task::JoinHandle};

use super::{Backend, CheckoutIdentity, Navigation, RPC_TIMEOUT, queue::read_queue};

pub(super) struct ParkedRuntime {
    client: AppServerClient,
    diagnostics: StderrTail,
    engine: WorkspaceEngine,
    reattach: oneshot::Sender<()>,
    task: JoinHandle<Option<Backend>>,
}

impl ParkedRuntime {
    pub(super) fn relay_connection(&self) -> Option<(AppServerClient, StderrTail)> {
        (!self.task.is_finished()).then(|| (self.client.clone(), self.diagnostics.clone()))
    }
}

impl Navigation {
    pub(super) async fn leave_checkout(&mut self) {
        let Some(backend) = &self.backend else {
            return;
        };
        let snapshot = backend.engine.snapshot();
        let Some(checkout) = snapshot.connection.workspace.checkout.clone() else {
            self.disconnect().await;
            return;
        };
        if snapshot.execution.active_turns.is_empty()
            && snapshot.execution.unresolved_commands.is_empty()
            && !self.owners.has_local_work(Some(&checkout))
            && !self
                .app
                .state::<crate::voice_ipc::VoiceIpc>()
                .owns_connection(&snapshot.connection)
            && !self
                .app
                .state::<crate::relay_ipc::RelayHost>()
                .owns(&snapshot.connection)
        {
            self.disconnect().await;
            return;
        }
        let backend = self.backend.take().expect("selected runtime");
        let client = backend.connection.client();
        if let Err(error) = self.login.retire(&client).await {
            eprintln!("{error}");
        }
        self.sandbox_setup = None;
        self.queues = Default::default();
        self.park_backend(checkout, backend);
    }

    pub(super) fn park_backend(&mut self, checkout: CheckoutIdentity, mut backend: Backend) {
        let client = backend.connection.client();
        let diagnostics = backend.connection.diagnostics().clone();
        let owners = self.owners.clone();
        let store = self.store.clone();
        let shutdown = self.shutdown_pending.clone();
        let changed = self.owner_changes.clone();
        let app = self.app.clone();
        let engine = backend.engine.clone();
        let (reattach, mut reattachment) = oneshot::channel();
        let backend_client = client.clone();
        let project_id = checkout.storage_key();
        let task = tokio::spawn(async move {
            loop {
                let event = tokio::select! {
                    biased;
                    next = &mut reattachment => {
                        if next.is_ok() {
                            return Some(backend);
                        }
                        None
                    }
                    event = backend.connection.next_event() => event,
                };
                let Some(event) = event else { break };
                let relay = app.state::<crate::relay_ipc::RelayHost>();
                if relay.observe(&app, backend_client.identity(), &event) {
                    continue;
                }
                let before = backend.engine.snapshot();
                backend.observe_edits(&event);
                if let ServerEvent::Notification { method, params } = &event
                    && method == "turn/completed"
                    && params["turn"]["status"] == "completed"
                    && let Some(chat_id) = params["threadId"].as_str()
                    && before
                        .writable_threads
                        .iter()
                        .any(|thread| thread.0 == chat_id)
                {
                    let key = SidebarChatKey {
                        project_id: project_id.clone(),
                        chat_id: chat_id.to_owned(),
                    };
                    if let Err(error) = store.sidebar_chat_finished(&key, true) {
                        eprintln!("{error}");
                    }
                }
                if let Err(error) = backend.observe_slash_event(&event, &store) {
                    eprintln!("{error}");
                }
                let voice = app.state::<crate::voice_ipc::VoiceIpc>();
                let routed = if voice.observe(&app, backend_client.identity(), &event) {
                    Ok(None)
                } else {
                    backend
                        .engine
                        .route_session_event(&backend_client, &store, event, RPC_TIMEOUT)
                        .await
                };
                if let Ok(Some(event)) = &routed {
                    crate::task_notifications::observe(
                        &app,
                        &store,
                        backend_client.identity(),
                        event,
                        |chat, turn| {
                            before
                                .execution
                                .active_turns
                                .iter()
                                .any(|active| active.thread.0 == chat && active.turn.0 == turn)
                        },
                    );
                }
                match routed {
                    Ok(Some(RoutedEvent::Conversation {
                        thread,
                        event: ServerEvent::Notification { method, params },
                    })) if method == "turn/completed"
                        && params["turn"]["status"] == "completed"
                        && !shutdown.load(Ordering::SeqCst) =>
                    {
                        let next: Result<(), super::Failure> = async {
                            let owner = backend_client.identity();
                            let checkout =
                                owner.workspace.checkout.as_ref().expect("parked checkout");
                            let ready = store
                                .legacy_queue(checkout, &thread, owner)?
                                .first()
                                .is_some_and(|entry| entry.status == LegacyQueueStatus::Ready);
                            if ready {
                                let _work = owners.acquire(owner)?;
                                let queue =
                                    read_queue(&backend.engine, &backend_client, &store, &thread)
                                        .await?;
                                if matches!(
                                    queue.for_selection(owner, &thread)?,
                                    QueueSnapshot::Unsupported
                                ) && !shutdown.load(Ordering::SeqCst)
                                {
                                    backend
                                        .engine
                                        .start_legacy_queue(
                                            &backend_client,
                                            &store,
                                            &thread,
                                            &queue,
                                            None,
                                            RPC_TIMEOUT,
                                        )
                                        .await?;
                                }
                            }
                            Ok(())
                        }
                        .await;
                        if let Err(error) = next {
                            eprintln!("{error}");
                        }
                    }
                    Ok(_) => {}
                    Err(error) => eprintln!("{error}"),
                }
                let current = backend.engine.snapshot();
                if before.execution != current.execution {
                    if let Err(error) =
                        owners.record_execution(backend_client.identity(), &before.execution)
                    {
                        eprintln!("{error}");
                    }
                    let _ = changed.try_send(());
                }
                if current.execution.active_turns.is_empty()
                    && current.execution.unresolved_commands.is_empty()
                    && !owners.has_local_work(current.connection.workspace.checkout.as_ref())
                    && !voice.owns_connection(&current.connection)
                    && !relay.owns(&current.connection)
                {
                    break;
                }
            }
            app.state::<crate::voice_ipc::VoiceIpc>()
                .connection_closed(&app, backend_client.identity());
            app.state::<crate::relay_ipc::RelayHost>()
                .disconnected(backend_client.identity());
            close_backend(&owners, backend).await;
            let _ = changed.try_send(());
            None
        });
        self.parked.insert(
            checkout,
            ParkedRuntime {
                client,
                diagnostics,
                engine,
                reattach,
                task,
            },
        );
    }

    pub(super) async fn take_parked(&mut self, checkout: &CheckoutIdentity) -> Option<Backend> {
        let parked = self.parked.remove(checkout)?;
        let _ = parked.reattach.send(());
        match parked.task.await {
            Ok(backend) => backend,
            Err(error) => {
                eprintln!("{error}");
                if let Err(error) = self.owners.retire(parked.client.identity()) {
                    eprintln!("{error}");
                }
                None
            }
        }
    }

    pub(super) fn runtime_connections(
        &self,
    ) -> impl Iterator<Item = (AppServerClient, WorkspaceEngine)> + '_ {
        self.backend
            .iter()
            .map(|item| (item.connection.client(), item.engine.clone()))
            .chain(
                self.parked
                    .values()
                    .filter(|parked| !parked.task.is_finished())
                    .map(|item| (item.client.clone(), item.engine.clone())),
            )
    }

    pub(super) async fn stop_parked(&mut self) {
        let tasks: Vec<_> = std::mem::take(&mut self.parked)
            .into_values()
            .map(|parked| {
                drop(parked.reattach);
                parked.task
            })
            .collect();
        for task in tasks {
            if let Err(error) = task.await {
                eprintln!("{error}");
            }
        }
    }
}

pub(super) async fn close_backend(owners: &RuntimeOwners, backend: Backend) {
    let state = backend.engine.snapshot();
    if state.connection.workspace.checkout.is_some()
        && let Err(error) = owners.retire(&state.connection)
    {
        eprintln!("{error}");
    }
    if let Err(error) = backend.connection.disconnect().await {
        eprintln!("{error}");
    }
}
