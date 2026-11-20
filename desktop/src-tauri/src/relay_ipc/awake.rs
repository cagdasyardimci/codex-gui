use std::time::Duration;

use tauri::{AppHandle, Manager, async_runtime::JoinHandle};

use crate::fixture::Verification;

pub(super) struct Hold {
    native: Option<JoinHandle<()>>,
    fixture: Option<std::path::PathBuf>,
}

impl Hold {
    pub(super) fn start(app: &AppHandle) -> Self {
        if matches!(
            *app.state::<Verification>(),
            Verification::RelayHost | Verification::RelayDevices
        ) {
            let fixture =
                std::env::var_os("CODEX_GUI_QA_RELAY_AWAKE").map(std::path::PathBuf::from);
            if let Some(path) = &fixture {
                record(path, "hold");
            }
            return Self {
                native: None,
                fixture,
            };
        }
        Self {
            native: Some(tauri::async_runtime::spawn(hold())),
            fixture: None,
        }
    }
}

impl Drop for Hold {
    fn drop(&mut self) {
        if let Some(task) = self.native.take() {
            task.abort();
        }
        if let Some(path) = &self.fixture {
            record(path, "release");
        }
    }
}

fn record(path: &std::path::Path, event: &str) {
    use std::io::Write;
    if let Ok(mut events) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(events, "{event}");
    }
}

#[cfg(target_os = "macos")]
async fn hold() {
    loop {
        // This system assertion applies only on AC power.
        if let Ok(mut child) = tokio::process::Command::new("/usr/bin/caffeinate")
            .arg("-s")
            .kill_on_drop(true)
            .spawn()
        {
            let _ = child.wait().await;
        }
        tokio::time::sleep(Duration::from_secs(10)).await;
    }
}

#[cfg(windows)]
async fn hold() {
    use windows::Win32::System::Power::{
        ES_CONTINUOUS, ES_SYSTEM_REQUIRED, GetSystemPowerStatus, SYSTEM_POWER_STATUS,
        SetThreadExecutionState,
    };

    let (_lifetime, retired) = std::sync::mpsc::channel::<()>();
    // The native assertion follows the operating system thread that set it.
    let _ = tauri::async_runtime::spawn_blocking(move || {
        loop {
            let mut power = SYSTEM_POWER_STATUS::default();
            let ac = unsafe { GetSystemPowerStatus(&mut power) }.is_ok() && power.ACLineStatus == 1;
            let state = if ac {
                ES_CONTINUOUS | ES_SYSTEM_REQUIRED
            } else {
                ES_CONTINUOUS
            };
            let _ = unsafe { SetThreadExecutionState(state) };
            if !matches!(
                retired.recv_timeout(Duration::from_secs(10)),
                Err(std::sync::mpsc::RecvTimeoutError::Timeout)
            ) {
                break;
            }
        }
        let _ = unsafe { SetThreadExecutionState(ES_CONTINUOUS) };
    })
    .await;
}

#[cfg(target_os = "linux")]
async fn hold() {
    let mut request = None;
    loop {
        if on_external_power() {
            if request.is_none() {
                request = tokio::time::timeout(Duration::from_secs(5), inhibit_idle())
                    .await
                    .ok()
                    .and_then(Result::ok);
            }
        } else {
            request = None;
        }
        tokio::time::sleep(Duration::from_secs(10)).await;
    }
}

#[cfg(target_os = "linux")]
async fn inhibit_idle() -> zbus::Result<zbus::zvariant::OwnedFd> {
    let bus = zbus::Connection::system().await?;
    let manager = zbus::Proxy::new(
        &bus,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )
    .await?;
    manager
        .call("Inhibit", &("idle", "Codex GUI", "Remote access", "block"))
        .await
}

#[cfg(target_os = "linux")]
fn on_external_power() -> bool {
    let Ok(supplies) = std::fs::read_dir("/sys/class/power_supply") else {
        return false;
    };
    let mut battery = false;
    for supply in supplies.flatten() {
        let path = supply.path();
        if std::fs::read_to_string(path.join("online")).is_ok_and(|value| value.trim() == "1") {
            return true;
        }
        battery |= std::fs::read_to_string(path.join("type"))
            .is_ok_and(|kind| kind.trim() == "Battery")
            && std::fs::read_to_string(path.join("scope"))
                .map_or(true, |scope| scope.trim() != "Device");
    }
    !battery
}
