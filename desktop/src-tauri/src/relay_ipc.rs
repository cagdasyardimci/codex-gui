use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::Mutex,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{BrowseError, RelayPhase, RelayStatus, RequestError, ServerEvent, StderrTail},
    identity::ConnectionIdentity,
    ipc::{IpcError, RemoteHostCommand, RemoteHostPhase, RemoteHostView},
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State, WebviewWindow};
use uuid::Uuid;

use crate::{
    fixture::Verification,
    project_ipc::{ProjectIpc, authorize_view},
    settings_ipc::SettingsIpc,
};

mod awake;

#[derive(Default)]
pub struct RelayHost(Mutex<Host>);

#[derive(Default)]
struct Host {
    file: PathBuf,
    preferences: Preferences,
    view: RemoteHostView,
    owner: Option<ConnectionIdentity>,
    observed: Option<RelayStatus>,
    revision: u64,
    diagnostics: Option<StderrTail>,
    awake: Option<awake::Hold>,
}

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Preferences {
    enabled: bool,
    keep_awake: bool,
    source: Option<Source>,
}

#[derive(Clone, Deserialize, Serialize)]
struct Source {
    path: PathBuf,
    identity: String,
}

impl RelayHost {
    pub fn load(&self, root: &Path) -> io::Result<()> {
        let file = root.join("remote-host-v1.json");
        let mut host = self.0.lock().expect("relay host lock poisoned");
        host.file = file.clone();
        let preferences: Preferences = match fs::read(&file) {
            Ok(bytes) => serde_json::from_slice(&bytes)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => Preferences::default(),
            Err(error) => return Err(error),
        };
        host.view.keep_awake = preferences.keep_awake;
        host.view.enabled = preferences.enabled;
        host.preferences = preferences;
        Ok(())
    }

    pub fn view(&self) -> RemoteHostView {
        self.0
            .lock()
            .expect("relay host lock poisoned")
            .view
            .clone()
    }

    pub fn needs_account(&self, app: &AppHandle) {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        host.view.available = false;
        host.view.phase = RemoteHostPhase::Disconnected;
        host.observed = None;
        host.update_awake(app);
    }

    pub fn source(&self) -> Option<CheckoutIdentity> {
        let source = self
            .0
            .lock()
            .expect("relay host lock poisoned")
            .preferences
            .source
            .clone()?;
        let identity = CheckoutIdentity::capture(&source.path).ok()?;
        (identity.storage_key() == source.identity).then_some(identity)
    }

    pub fn wants_reconnect(&self) -> bool {
        let host = self.0.lock().expect("relay host lock poisoned");
        host.preferences.enabled && host.owner.is_none()
    }

    pub fn change_enabled(
        &self,
        app: &AppHandle,
        enabled: bool,
        source: Option<&CheckoutIdentity>,
    ) -> io::Result<()> {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        let mut preferences = host.preferences.clone();
        preferences.enabled = enabled;
        if let Some(source) = source {
            preferences.source = Some(Source {
                path: source.canonical_path().to_path_buf(),
                identity: source.storage_key(),
            });
        }
        host.save(preferences)?;
        host.view.phase = if enabled {
            RemoteHostPhase::Connecting
        } else {
            RemoteHostPhase::Disabled
        };
        host.update_awake(app);
        Ok(())
    }

    pub fn keep_awake(&self, app: &AppHandle, awake: bool) -> io::Result<()> {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        let preferences = Preferences {
            keep_awake: awake,
            ..host.preferences.clone()
        };
        host.save(preferences)?;
        host.update_awake(app);
        Ok(())
    }

    pub fn attach(&self, owner: &ConnectionIdentity, diagnostics: StderrTail) -> u64 {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        if host.owner.as_ref() != Some(owner) {
            host.observed = None;
            host.owner = Some(owner.clone());
            host.diagnostics = Some(diagnostics);
            host.revision += 1;
        }
        host.revision
    }

    pub fn owns(&self, owner: &ConnectionIdentity) -> bool {
        let host = self.0.lock().expect("relay host lock poisoned");
        host.view.enabled && host.owner.as_ref() == Some(owner)
    }

    pub fn disconnected(&self, owner: &ConnectionIdentity) {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        if host.owner.as_ref() == Some(owner) {
            host.owner = None;
            host.observed = None;
            host.diagnostics = None;
            host.awake = None;
            if host.view.enabled {
                host.view.phase = RemoteHostPhase::Disconnected;
            }
        }
    }

    pub fn observe(
        &self,
        app: &AppHandle,
        owner: &ConnectionIdentity,
        event: &ServerEvent,
    ) -> bool {
        let ServerEvent::Notification { method, params } = event else {
            return false;
        };
        if method != "remoteControl/status/changed" {
            return false;
        }
        let mut host = self.0.lock().expect("relay host lock poisoned");
        if host.owner.as_ref() == Some(owner)
            && let Ok(status) = serde_json::from_value(params.clone())
        {
            host.revision += 1;
            host.update(app, status);
        }
        true
    }

    pub fn finish(
        &self,
        app: &AppHandle,
        owner: &ConnectionIdentity,
        revision: u64,
        result: Result<RelayStatus, BrowseError>,
    ) {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        if host.owner.as_ref() != Some(owner) || host.revision != revision {
            return;
        }
        match result {
            Ok(status) => host.update(app, status),
            Err(BrowseError::Request(RequestError::Remote(error))) if error.code == -32601 => {
                host.view.available = false;
                host.awake = None;
            }
            Err(BrowseError::Request(RequestError::Remote(error)))
                if error.code == 409 || duplicate(&error.message) =>
            {
                host.view.phase = RemoteHostPhase::Duplicate;
                host.view.available = true;
                host.observed = None;
                host.update_awake(app);
            }
            Err(_) => {}
        }
    }
}

impl Host {
    fn save(&mut self, preferences: Preferences) -> io::Result<()> {
        let folder = self.file.parent().ok_or(io::ErrorKind::NotFound)?;
        let mut swap = tempfile::NamedTempFile::new_in(folder)?;
        serde_json::to_writer(&mut swap, &preferences)?;
        swap.flush()?;
        swap.as_file().sync_all()?;
        swap.persist(&self.file)?;
        self.view.enabled = preferences.enabled;
        self.view.keep_awake = preferences.keep_awake;
        self.preferences = preferences;
        Ok(())
    }

    fn update(&mut self, app: &AppHandle, status: RelayStatus) {
        self.view.available = true;
        self.view.phase = match status.status {
            RelayPhase::Disabled => RemoteHostPhase::Disabled,
            RelayPhase::Connecting => RemoteHostPhase::Connecting,
            RelayPhase::Connected
                if status
                    .environment_id
                    .as_deref()
                    .is_some_and(|id| !id.is_empty()) =>
            {
                RemoteHostPhase::Connected
            }
            RelayPhase::Errored
                if self.view.phase == RemoteHostPhase::Duplicate
                    || self.diagnostics.as_ref().is_some_and(|stderr| {
                        duplicate(&String::from_utf8_lossy(&stderr.snapshot()))
                    }) =>
            {
                RemoteHostPhase::Duplicate
            }
            _ => RemoteHostPhase::Disconnected,
        };
        self.observed = Some(status);
        self.update_awake(app);
    }

    fn update_awake(&mut self, app: &AppHandle) {
        let hold = self.view.enabled
            && self.view.keep_awake
            && self.view.phase == RemoteHostPhase::Connected;
        if hold && self.awake.is_none() {
            self.awake = Some(awake::Hold::start(app));
        } else if !hold {
            self.awake = None;
        }
    }
}

fn duplicate(message: &str) -> bool {
    message
        .to_ascii_lowercase()
        .contains("remote app server already online")
}

#[tauri::command]
pub fn remote_host_snapshot(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    session: Uuid,
) -> Result<RemoteHostView, IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(session)?;
    Ok(window.state::<RelayHost>().view())
}

#[tauri::command]
pub async fn change_remote_host(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    session: Uuid,
    command: RemoteHostCommand,
) -> Result<RemoteHostView, IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(session)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    navigation.change_remote_host(session, command).await
}

#[tauri::command]
pub fn relay_host_fixture_view(
    window: WebviewWindow,
    verification: State<'_, Verification>,
) -> Result<RemoteHostView, IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::RelayHost {
        return Err(IpcError::UnauthorizedWindow);
    }
    Ok(window.state::<RelayHost>().view())
}
