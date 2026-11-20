use std::{
    collections::HashSet,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use codex_gui_core::{
    codex::{CodexBrowser, RelayClient, RelayPairing},
    ipc::{
        RemoteDeviceCommand, RemoteDeviceScope, RemoteDeviceView, RemoteDevicesView,
        RemotePairingView,
    },
};
use qrcode::{Color, EcLevel, QrCode};
use tauri_plugin_clipboard_manager::ClipboardExt;

use super::*;

const DEVICE_TIMEOUT: Duration = Duration::from_secs(8);
const MAX_PAIRING_SECONDS: i64 = 24 * 60 * 60;

#[derive(Default)]
pub(super) struct Devices {
    scope: Option<RemoteDeviceScope>,
    binding: Option<Binding>,
    revision: u64,
    pairing_pending: Option<Uuid>,
    pairing: Option<Pairing>,
    devices: Vec<Device>,
    revoking: HashSet<String>,
}

#[derive(Clone, PartialEq, Eq)]
pub(super) struct Authority {
    pub owner: ConnectionIdentity,
    pub installation: String,
    pub environment: String,
}

struct Binding {
    id: Uuid,
    authority: Authority,
}

struct Pairing {
    view: RemotePairingView,
    code: String,
}

struct Device {
    view: RemoteDeviceView,
    client_id: String,
}

impl Devices {
    pub(super) fn reconcile(&mut self, authority: Option<Authority>) {
        if self.binding.as_ref().map(|binding| &binding.authority) == authority.as_ref() {
            return;
        }
        self.binding = authority.map(|authority| Binding {
            id: Uuid::new_v4(),
            authority,
        });
        self.clear();
    }

    pub(super) fn retire_session(&mut self, session: Uuid) {
        if self.scope.is_some_and(|scope| scope.session == session) {
            self.scope = None;
            self.clear();
        }
    }

    fn clear(&mut self) {
        self.revision += 1;
        self.devices.clear();
        self.revoking.clear();
        self.pairing_pending = None;
        self.pairing = None;
    }

    fn view(&mut self) -> RemoteDevicesView {
        if self
            .pairing
            .as_ref()
            .is_some_and(|pairing| pairing.view.expires_at <= seconds_now())
        {
            self.pairing = None;
        }
        RemoteDevicesView {
            connected: self.binding.is_some(),
            environment: self.binding.as_ref().map(|binding| binding.id),
            pairing: self.pairing.as_ref().map(|pairing| pairing.view.clone()),
            devices: self
                .devices
                .iter()
                .map(|device| device.view.clone())
                .collect(),
        }
    }

    fn replace_devices(&mut self, next: Vec<RelayClient>) {
        self.devices = next
            .into_iter()
            .filter(|device| !self.revoking.contains(&device.client_id))
            .map(|device| {
                let id = self
                    .devices
                    .iter()
                    .find(|item| item.client_id == device.client_id)
                    .map_or_else(Uuid::new_v4, |item| item.view.id);
                let name = [device.display_name, device.device_model, device.platform]
                    .into_iter()
                    .flatten()
                    .find(|name| !name.trim().is_empty())
                    .unwrap_or_else(|| "Device".into());
                Device {
                    view: RemoteDeviceView {
                        id,
                        name: name.trim().chars().take(160).collect(),
                    },
                    client_id: device.client_id,
                }
            })
            .collect();
    }
}

impl RelayHost {
    pub fn retire_device_session(&self, session: Uuid) {
        self.0
            .lock()
            .expect("relay host lock poisoned")
            .devices
            .retire_session(session);
    }

    fn with_devices<T>(
        &self,
        scope: RemoteDeviceScope,
        work: impl FnOnce(&mut Devices) -> Result<T, IpcError>,
    ) -> Result<T, IpcError> {
        let mut host = self.0.lock().expect("relay host lock poisoned");
        let devices = &mut host.devices;
        if devices.scope != Some(scope) {
            return Err(IpcError::StaleSelection);
        }
        work(devices)
    }
}

#[tauri::command]
pub fn open_relay_devices(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    scope: RemoteDeviceScope,
) -> Result<RemoteDevicesView, IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(scope.session)?;
    let relay = window.state::<RelayHost>();
    let mut host = relay.0.lock().expect("relay host lock poisoned");
    host.devices.scope = Some(scope);
    host.devices.clear();
    Ok(host.devices.view())
}

#[tauri::command]
pub fn close_relay_devices(
    window: WebviewWindow,
    scope: RemoteDeviceScope,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let _ = window.state::<RelayHost>().with_devices(scope, |devices| {
        devices.scope = None;
        devices.clear();
        Ok(())
    });
    Ok(())
}

#[tauri::command]
pub fn relay_devices_snapshot(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    scope: RemoteDeviceScope,
) -> Result<RemoteDevicesView, IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(scope.session)?;
    window
        .state::<RelayHost>()
        .with_devices(scope, |devices| Ok(devices.view()))
}

#[tauri::command]
pub fn copy_relay_pairing_code(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    scope: RemoteDeviceScope,
    id: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(scope.session)?;
    window.state::<RelayHost>().with_devices(scope, |devices| {
        let pairing = devices
            .pairing
            .as_ref()
            .filter(|pairing| pairing.view.id == id && pairing.view.expires_at > seconds_now())
            .ok_or(IpcError::StaleSelection)?;
        if *window.state::<Verification>() == Verification::RelayDevices {
            return Ok(());
        }
        window
            .clipboard()
            .write_text(&pairing.view.manual_code)
            .map_err(|_| IpcError::ProjectUnavailable)
    })
}

#[tauri::command]
pub async fn change_relay_devices(
    window: WebviewWindow,
    project: State<'_, ProjectIpc>,
    settings: State<'_, SettingsIpc>,
    scope: RemoteDeviceScope,
    command: RemoteDeviceCommand,
) -> Result<RemoteDevicesView, IpcError> {
    authorize_view(&window)?;
    settings.authorize_session(scope.session)?;
    let relay = window.state::<RelayHost>();
    if matches!(command, RemoteDeviceCommand::ClosePairing) {
        return relay.with_devices(scope, |devices| {
            devices.pairing = None;
            devices.pairing_pending = None;
            Ok(devices.view())
        });
    }
    let (binding, authority) = relay.with_devices(scope, |devices| {
        let binding = devices.binding.as_ref().ok_or(IpcError::StaleSelection)?;
        Ok((binding.id, binding.authority.clone()))
    })?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    let client = navigation.relay_client(authority.owner).await?;
    let operation = Operation {
        app: window.app_handle(),
        relay: &relay,
        scope,
        binding,
        environment: authority.environment,
        browser: CodexBrowser::new(client),
    };
    match command {
        RemoteDeviceCommand::Refresh => operation.refresh().await,
        RemoteDeviceCommand::BeginPairing => operation.pair().await,
        RemoteDeviceCommand::CheckPairing(id) => operation.check_pairing(id).await,
        RemoteDeviceCommand::Revoke(id) => operation.revoke(id).await,
        RemoteDeviceCommand::ClosePairing => unreachable!("closed before connecting"),
    }?;
    settings.authorize_session(scope.session)?;
    operation.with_devices(|devices| Ok(devices.view()))
}

struct Operation<'a> {
    app: &'a AppHandle,
    relay: &'a RelayHost,
    scope: RemoteDeviceScope,
    binding: Uuid,
    environment: String,
    browser: CodexBrowser,
}

impl Operation<'_> {
    fn with_devices<T>(
        &self,
        work: impl FnOnce(&mut Devices) -> Result<T, IpcError>,
    ) -> Result<T, IpcError> {
        self.relay.with_devices(self.scope, |devices| {
            if devices.binding.as_ref().map(|binding| binding.id) != Some(self.binding) {
                return Err(IpcError::StaleSelection);
            }
            work(devices)
        })
    }

    async fn refresh(&self) -> Result<(), IpcError> {
        let revision = self.with_devices(|devices| {
            devices.revision += 1;
            Ok(devices.revision)
        })?;
        let result = self
            .browser
            .relay_clients(&self.environment, DEVICE_TIMEOUT)
            .await;
        self.with_devices(|devices| {
            if devices.revision == revision
                && let Ok(result) = result
            {
                devices.replace_devices(result);
            }
            Ok(())
        })
    }

    async fn pair(&self) -> Result<(), IpcError> {
        let id = Uuid::new_v4();
        self.with_devices(|devices| {
            if devices.pairing_pending.is_some() {
                return Err(IpcError::StaleSelection);
            }
            devices.pairing = None;
            devices.pairing_pending = Some(id);
            Ok(())
        })?;
        let next = self
            .browser
            .start_relay_pairing(DEVICE_TIMEOUT)
            .await
            .ok()
            .and_then(|reply| pair_view(id, reply, &self.environment));
        let expiry = next.as_ref().map(|pairing| pairing.view.expires_at);
        self.with_devices(|devices| {
            if devices.pairing_pending != Some(id) {
                return Err(IpcError::StaleSelection);
            }
            devices.pairing_pending = None;
            devices.pairing = next;
            Ok(())
        })?;
        if let Some(expiry) = expiry {
            let app = self.app.clone();
            let scope = self.scope;
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(Duration::from_secs(
                    expiry.saturating_sub(seconds_now()).max(0) as u64,
                ))
                .await;
                let _ = app.state::<RelayHost>().with_devices(scope, |devices| {
                    if devices
                        .pairing
                        .as_ref()
                        .is_some_and(|pairing| pairing.view.id == id)
                    {
                        devices.pairing = None;
                    }
                    Ok(())
                });
            });
        }
        Ok(())
    }

    async fn check_pairing(&self, id: Uuid) -> Result<(), IpcError> {
        let code = self.with_devices(|devices| {
            Ok(devices
                .pairing
                .as_ref()
                .filter(|pairing| pairing.view.id == id && pairing.view.expires_at > seconds_now())
                .map(|pairing| pairing.code.clone()))
        })?;
        let Some(code) = code else { return Ok(()) };
        if matches!(
            self.browser
                .relay_pairing_claimed(&code, DEVICE_TIMEOUT)
                .await,
            Ok(true)
        ) {
            let retired = self.with_devices(|devices| {
                if devices
                    .pairing
                    .as_ref()
                    .is_some_and(|pairing| pairing.view.id == id)
                {
                    devices.pairing = None;
                    return Ok(true);
                }
                Ok(false)
            })?;
            if retired {
                self.refresh().await?;
            }
        }
        Ok(())
    }

    async fn revoke(&self, id: Uuid) -> Result<(), IpcError> {
        let client = self.with_devices(|devices| {
            let index = devices
                .devices
                .iter()
                .position(|device| device.view.id == id)
                .ok_or(IpcError::StaleSelection)?;
            devices.revision += 1;
            let client = devices.devices.remove(index).client_id;
            devices.revoking.insert(client.clone());
            Ok(client)
        })?;
        let result = self
            .browser
            .revoke_relay_client(&self.environment, &client, DEVICE_TIMEOUT)
            .await;
        self.with_devices(|devices| {
            devices.revision += 1;
            devices.revoking.remove(&client);
            Ok(())
        })?;
        if result.is_ok() {
            self.refresh().await?;
        }
        Ok(())
    }
}

fn pair_view(id: Uuid, reply: RelayPairing, environment: &str) -> Option<Pairing> {
    let life = reply.expires_at.saturating_sub(seconds_now());
    if reply.environment_id != environment
        || !(1..=MAX_PAIRING_SECONDS).contains(&life)
        || reply.pairing_code.is_empty()
        || reply.pairing_code.len() > 1024
        || reply.manual_pairing_code.is_empty()
        || reply.manual_pairing_code.len() > 128
        || reply.manual_pairing_code.chars().any(char::is_control)
    {
        return None;
    }
    let mut url = tauri::Url::parse("https://chatgpt.com/codex/pair").ok()?;
    url.query_pairs_mut()
        .append_pair("pairing_code", &reply.pairing_code);
    let qr = QrCode::with_error_correction_level(url.as_str().as_bytes(), EcLevel::H).ok()?;
    let width = qr.width();
    let cells = qr
        .into_colors()
        .into_iter()
        .map(|color| color == Color::Dark)
        .collect();
    Some(Pairing {
        code: reply.pairing_code,
        view: RemotePairingView {
            id,
            expires_at: reply.expires_at,
            manual_code: reply.manual_pairing_code,
            width,
            cells,
        },
    })
}

fn seconds_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
