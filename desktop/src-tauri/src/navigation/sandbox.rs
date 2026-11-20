use std::time::Duration;

use codex_gui_core::{
    codex::{
        AppServerClient, CodexBrowser, WindowsSandboxReadiness, WindowsSandboxSetupCompleted,
        WindowsSandboxSetupMode,
    },
    identity::ConnectionIdentity,
    ipc::{IpcError, WriteAccess},
};
use tokio::time::Instant;

use super::{Failure, Navigation, RPC_TIMEOUT, report};

const SETUP_TIMEOUT: Duration = Duration::from_secs(90);

pub(super) struct SandboxSetup {
    owner: ConnectionIdentity,
    mode: WindowsSandboxSetupMode,
    deadline: Instant,
    action: WriteAccess,
}

impl Navigation {
    pub(super) async fn refresh_write_access(&mut self, client: &AppServerClient) {
        if self.sandbox_setup.is_some() {
            return;
        }
        self.view.write_access = if self.selection.is_none() {
            WriteAccess::Unavailable
        } else if !self.windows_sandbox {
            WriteAccess::Ready
        } else {
            match CodexBrowser::new(client.clone())
                .windows_sandbox_readiness(RPC_TIMEOUT)
                .await
            {
                Ok(WindowsSandboxReadiness::Ready) => WriteAccess::Ready,
                Ok(WindowsSandboxReadiness::NotConfigured) => WriteAccess::SetupSandbox,
                Ok(WindowsSandboxReadiness::UpdateRequired) => WriteAccess::UpdateSandbox,
                Err(error) => {
                    eprintln!("{error}");
                    WriteAccess::Unavailable
                }
            }
        };
        self.publish_navigation();
    }

    pub(super) async fn start_sandbox_setup(&mut self) -> Result<(), IpcError> {
        let action = self.view.write_access;
        let (mode, in_progress) = match action {
            WriteAccess::SetupSandbox => (
                WindowsSandboxSetupMode::Unelevated,
                WriteAccess::SettingUpSandbox,
            ),
            WriteAccess::UpdateSandbox => (
                WindowsSandboxSetupMode::Elevated,
                WriteAccess::UpdatingSandbox,
            ),
            _ => return Err(IpcError::StaleSelection),
        };
        let client = self
            .backend
            .as_ref()
            .ok_or(IpcError::RetiredWorkspace)?
            .connection
            .client();
        let browser = CodexBrowser::new(client.clone());
        match browser.start_windows_sandbox_setup(mode, RPC_TIMEOUT).await {
            Ok(true) => {}
            Ok(false) => return Err(IpcError::ProjectUnavailable),
            Err(error) => {
                self.disconnect().await;
                return Err(report(error.into()));
            }
        }
        self.sandbox_setup = Some(SandboxSetup {
            owner: client.identity().clone(),
            mode,
            deadline: Instant::now() + SETUP_TIMEOUT,
            action,
        });
        self.view.write_access = in_progress;
        self.publish_navigation();
        Ok(())
    }

    pub(super) async fn handle_sandbox_completion(
        &mut self,
        owner: &ConnectionIdentity,
        completed: WindowsSandboxSetupCompleted,
    ) -> Result<(), Failure> {
        let Some(pending) = self
            .sandbox_setup
            .as_ref()
            .filter(|pending| &pending.owner == owner && pending.mode == completed.mode)
        else {
            return Ok(());
        };
        let action = pending.action;
        self.sandbox_setup = None;
        if !completed.success {
            self.view.write_access = action;
            self.publish_navigation();
            eprintln!("Windows sandbox setup failed");
            return Ok(());
        }
        // Codex reads the persisted mode when app-server starts. A completion
        // event alone does not establish readiness for writable operations.
        self.disconnect().await;
        self.refresh().await
    }

    pub(super) async fn expire_sandbox_setup(&mut self, now: Instant) {
        if self
            .sandbox_setup
            .as_ref()
            .is_some_and(|pending| pending.deadline <= now)
        {
            eprintln!("Windows sandbox setup timed out");
            self.disconnect().await;
        }
    }
}
