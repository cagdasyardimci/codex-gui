use codex_gui_core::{
    codex::{Account, StderrTail},
    worktree::{WorktreePhase, WorktreeStore},
};

use super::*;

impl Navigation {
    pub(super) async fn restore_relay(&mut self) {
        let host = self.app.state::<RelayHost>();
        if self.quit.is_some() || !host.wants_reconnect() {
            return;
        }
        let Some(source) = host.source() else { return };
        if let Err(error) = self.relay_request(&source, Some(true)).await {
            eprintln!("Could not restore the relay host: {error}");
        }
    }

    pub(super) async fn apply_relay(
        &mut self,
        command: RemoteHostCommand,
    ) -> Result<RemoteHostView, IpcError> {
        let app = self.app.clone();
        let host = app.state::<RelayHost>();
        match command {
            RemoteHostCommand::KeepAwake(awake) => host
                .keep_awake(&app, awake)
                .map_err(|error| report(error.into()))?,
            RemoteHostCommand::Enabled(true) if !host.view().enabled => {
                let source = self.relay_source().map_err(report)?;
                host.change_enabled(&app, true, Some(&source))
                    .map_err(|error| report(error.into()))?;
                self.relay_request(&source, Some(true))
                    .await
                    .map_err(report)?;
            }
            RemoteHostCommand::Enabled(false) if host.view().enabled => {
                let source = host.source();
                host.change_enabled(&app, false, None)
                    .map_err(|error| report(error.into()))?;
                if let Some(source) = source {
                    self.relay_request(&source, Some(false))
                        .await
                        .map_err(report)?;
                }
            }
            RemoteHostCommand::Refresh => {
                let source = if host.view().enabled {
                    host.source()
                } else {
                    self.relay_source().ok()
                };
                if let Some(source) = source {
                    self.relay_request(&source, None).await.map_err(report)?;
                }
            }
            _ => {}
        }
        Ok(host.view())
    }

    fn relay_source(&self) -> Result<CheckoutIdentity, Failure> {
        let checkout = &self
            .selection
            .as_ref()
            .ok_or("Select a source workspace")?
            .checkout;
        checkout.revalidate()?;
        let worktrees = WorktreeStore::open(&self.worktree_records)?.snapshot()?;
        match worktrees.records.iter().find(|record| {
            record.phase == WorktreePhase::Active
                && checkout.validate_reported(&record.checkout_path).is_ok()
        }) {
            Some(record) => Ok(CheckoutIdentity::capture(&record.source_project_path)?),
            None => Ok(checkout.clone()),
        }
    }

    async fn relay_request(
        &mut self,
        source: &CheckoutIdentity,
        enabled: Option<bool>,
    ) -> Result<(), Failure> {
        let (client, diagnostics, parked) = self.relay_connection(source).await?;
        let host = self.app.state::<RelayHost>();
        let owner = client.identity();
        let revision = host.attach(owner, diagnostics);
        if let Some(backend) = parked {
            self.park_backend(source.clone(), backend);
        }
        let browser = CodexBrowser::new(client.clone());
        if enabled != Some(false)
            && !matches!(
                browser.account(RPC_TIMEOUT).await?.account,
                Some(Account::Chatgpt { .. })
            )
        {
            self.app.state::<RelayHost>().needs_account(&self.app);
            return Ok(());
        }
        let result = match enabled {
            Some(false) => browser.set_relay_enabled(false, RPC_TIMEOUT).await,
            Some(true) => browser.set_relay_enabled(true, RPC_TIMEOUT).await,
            None => browser.relay_status(RPC_TIMEOUT).await,
        };
        self.app
            .state::<RelayHost>()
            .finish(&self.app, owner, revision, result);
        Ok(())
    }

    async fn relay_connection(
        &mut self,
        source: &CheckoutIdentity,
    ) -> Result<(AppServerClient, StderrTail, Option<Backend>), Failure> {
        source.revalidate()?;
        if self
            .selection
            .as_ref()
            .is_some_and(|selection| &selection.checkout == source)
        {
            let client = self.connect().await?;
            let process = &self
                .backend
                .as_ref()
                .expect("selected backend connected")
                .connection;
            return Ok((client, process.diagnostics().clone(), None));
        }
        if let Some((client, diagnostics)) = self
            .parked
            .get(source)
            .and_then(ParkedRuntime::relay_connection)
        {
            return Ok((client, diagnostics, None));
        }
        let identity = ConnectionIdentity {
            workspace: WorkspaceIdentity {
                session: CheckoutSessionId(Uuid::new_v4()),
                checkout: Some(source.clone()),
            },
            generation: ConnectionGeneration(1),
        };
        let backend = self.open_backend(identity).await?;
        Ok((
            backend.connection.client(),
            backend.connection.diagnostics().clone(),
            Some(backend),
        ))
    }
}
