use std::{
    env,
    error::Error,
    path::{Path, PathBuf},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{AppServerConnection, ClientInfo, CodexExecutable, ServerEvent},
    identity::{CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, WorkspaceIdentity},
};
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const SETUP_TIMEOUT: Duration = Duration::from_secs(90);
const MODE: &str = "unelevated";

#[derive(Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
enum Readiness {
    NotConfigured,
    UpdateRequired,
    Ready,
}

#[derive(Deserialize)]
struct ReadinessReply {
    status: Readiness,
}

#[derive(Deserialize)]
struct SetupReply {
    started: bool,
}

#[derive(Deserialize)]
struct SetupCompleted {
    mode: String,
    success: bool,
    error: Option<String>,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args_os().skip(1);
    let executable = PathBuf::from(arguments.next().ok_or("expected Codex executable path")?);
    let checkout = PathBuf::from(
        arguments
            .next()
            .ok_or("expected disposable checkout path")?,
    );
    if arguments.next().is_some() {
        return Err("unexpected arguments".into());
    }
    let codex = CodexExecutable::discover(Some(&executable))?;
    let workspace = WorkspaceIdentity {
        session: CheckoutSessionId(Uuid::from_u128(1)),
        checkout: Some(CheckoutIdentity::capture(&checkout)?),
    };
    let mut connection = connect(&codex, &workspace, 1).await?;
    let initial = readiness(&connection).await?;
    println!("Initial Windows sandbox readiness: {initial:?}");
    if initial != Readiness::NotConfigured {
        return Err("expected a fresh Windows sandbox profile".into());
    }
    setup(&mut connection, &checkout).await?;
    connection.disconnect().await?;

    let connection = connect(&codex, &workspace, 2).await?;
    let persisted = readiness(&connection).await?;
    println!("Windows sandbox readiness after reconnect: {persisted:?}");
    connection.disconnect().await?;
    if persisted != Readiness::Ready {
        return Err("Windows sandbox setup did not persist readiness".into());
    }
    Ok(())
}

async fn connect(
    executable: &CodexExecutable,
    workspace: &WorkspaceIdentity,
    generation: u64,
) -> Result<AppServerConnection, Box<dyn Error>> {
    Ok(AppServerConnection::connect(
        executable,
        ConnectionIdentity {
            workspace: workspace.clone(),
            generation: ConnectionGeneration(generation),
        },
        ClientInfo {
            name: "codex_gui_sandbox_probe",
            title: "Codex GUI Sandbox Probe",
            version: "0.1.0",
        },
        REQUEST_TIMEOUT,
    )
    .await?)
}

async fn readiness(connection: &AppServerConnection) -> Result<Readiness, Box<dyn Error>> {
    let result = connection
        .client()
        .request("windowsSandbox/readiness", Value::Null, REQUEST_TIMEOUT)
        .await?;
    Ok(serde_json::from_value::<ReadinessReply>(result)?.status)
}

async fn setup(
    connection: &mut AppServerConnection,
    checkout: &Path,
) -> Result<(), Box<dyn Error>> {
    let result = connection
        .client()
        .request(
            "windowsSandbox/setupStart",
            json!({"mode": MODE, "cwd": checkout}),
            REQUEST_TIMEOUT,
        )
        .await?;
    if !serde_json::from_value::<SetupReply>(result)?.started {
        return Err("Windows sandbox setup did not start".into());
    }
    let completed = tokio::time::timeout(SETUP_TIMEOUT, async {
        while let Some(event) = connection.next_event().await {
            if let ServerEvent::Notification { method, params } = event
                && method == "windowsSandbox/setupCompleted"
            {
                let completed = serde_json::from_value::<SetupCompleted>(params)?;
                if completed.mode == MODE {
                    return Ok(completed);
                }
            }
        }
        Err::<SetupCompleted, Box<dyn Error>>(
            "connection closed before sandbox setup completed".into(),
        )
    })
    .await??;
    if !completed.success {
        return Err(completed
            .error
            .unwrap_or_else(|| "Windows sandbox setup failed".into())
            .into());
    }
    println!("Windows sandbox setup completed in {MODE} mode");
    Ok(())
}
