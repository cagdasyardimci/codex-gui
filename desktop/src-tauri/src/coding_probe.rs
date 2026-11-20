use std::{
    env,
    error::Error,
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{AppServerConnection, ClientInfo, CodexBrowser, CodexExecutable, ServerEvent},
    identity::{CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, WorkspaceIdentity},
};
use serde::Deserialize;
use serde_json::{Value, json};
use tempfile::Builder;
use tokio::{process::Command, time::timeout};
use uuid::Uuid;

pub const ARGUMENT: &str = "--verify-coding-turn";
const RPC_TIMEOUT: Duration = Duration::from_secs(20);
const TURN_TIMEOUT: Duration = Duration::from_secs(180);
const MARKER_FILE: &str = "codex-gui-probe.txt";
type ProbeError = Box<dyn Error + Send + Sync>;

#[derive(Deserialize)]
struct StartedThread {
    thread: ThreadLocation,
    cwd: PathBuf,
}

#[derive(Deserialize)]
struct ThreadLocation {
    id: String,
    cwd: PathBuf,
}

pub fn open_report(path: &Path) -> Result<File, ProbeError> {
    if !path.is_absolute() {
        return Err("coding probe report path must be absolute".into());
    }
    Ok(OpenOptions::new().create_new(true).write(true).open(path)?)
}

pub async fn run(mut report: File) -> Result<(), ProbeError> {
    match run_turn().await {
        Ok((executable, version)) => {
            writeln!(report, "Default-policy coding probe completed")?;
            writeln!(report, "Codex executable: {}", executable.display())?;
            writeln!(report, "Codex CLI version: {version}")?;
            Ok(())
        }
        Err(error) => {
            writeln!(report, "Coding probe failed: {error}")?;
            Err(error)
        }
    }
}

async fn run_turn() -> Result<(PathBuf, String), ProbeError> {
    let codex_home = env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .ok_or("set CODEX_HOME to an isolated Codex profile")?;
    if !codex_home.is_absolute() || !codex_home.is_dir() {
        return Err("CODEX_HOME must name an existing absolute directory".into());
    }
    let executable = CodexExecutable::discover(None)?;
    let temporary = Builder::new().prefix("codex-gui-coding-").tempdir()?;
    let checkout_path = temporary.path().join("Project café");
    fs::create_dir(&checkout_path)?;
    let checkout = CheckoutIdentity::capture(&checkout_path)?;
    initialize_git(&checkout_path).await?;

    let marker = format!("codex-gui-probe-{}", Uuid::new_v4());
    fs::write(checkout_path.join(MARKER_FILE), format!("{marker}\n"))?;

    let mut connection = AppServerConnection::connect(
        &executable,
        ConnectionIdentity {
            workspace: WorkspaceIdentity {
                session: CheckoutSessionId(Uuid::new_v4()),
                checkout: Some(checkout.clone()),
            },
            generation: ConnectionGeneration(1),
        },
        ClientInfo {
            name: "codex_gui_coding_probe",
            title: "Codex GUI Coding Probe",
            version: env!("CARGO_PKG_VERSION"),
        },
        RPC_TIMEOUT,
    )
    .await?;
    let version = connection.compatibility().version().to_string();
    let client = connection.client();
    let account = CodexBrowser::new(client.clone())
        .account(RPC_TIMEOUT)
        .await?;
    if account.requires_openai_auth && account.account.is_none() {
        return Err("sign in to Codex in the isolated profile before running the probe".into());
    }

    let started = client
        .request("thread/start", json!({"cwd": checkout_path}), RPC_TIMEOUT)
        .await?;
    let started: StartedThread = serde_json::from_value(started)?;
    checkout.validate_reported(&started.cwd)?;
    checkout.validate_reported(&started.thread.cwd)?;
    let thread = started.thread.id;
    let outcome = async {
        let reply = client.request(
            "turn/start",
            json!({
                "threadId": thread,
                "cwd": checkout_path,
                "clientUserMessageId": Uuid::new_v4().to_string(),
                "input": [{
                    "type": "text",
                    "text": format!("Use a local shell command to read {MARKER_FILE} in this checkout. Print the contents to command output and report completion."),
                }],
            }),
            RPC_TIMEOUT,
        ).await?;
        let turn = reply["turn"]["id"]
            .as_str()
            .filter(|id| !id.is_empty())
            .ok_or("Codex did not assign a turn ID")?;
        timeout(
            TURN_TIMEOUT,
            observe_turn(&mut connection, &checkout, &thread, turn, &marker),
        )
        .await?
    }.await;

    if outcome.is_err() {
        let retained = temporary.keep();
        eprintln!("Retained the disposable checkout at {}", retained.display());
    }
    let exit = connection.disconnect().await;
    outcome?;
    exit?;
    Ok((executable.path().to_path_buf(), version))
}

async fn initialize_git(checkout: &Path) -> Result<(), ProbeError> {
    let result = timeout(
        RPC_TIMEOUT,
        Command::new("git")
            .args(["init", "--quiet", "--template="])
            .current_dir(checkout)
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE")
            .env_remove("GIT_COMMON_DIR")
            .kill_on_drop(true)
            .output(),
    )
    .await??;
    if !result.status.success() {
        return Err(format!("git init exited with {}", result.status).into());
    }
    Ok(())
}

async fn observe_turn(
    connection: &mut AppServerConnection,
    checkout: &CheckoutIdentity,
    thread: &str,
    turn: &str,
    marker: &str,
) -> Result<(), ProbeError> {
    let mut found_command = false;
    while let Some(event) = connection.next_event().await {
        match event {
            ServerEvent::Notification { method, params }
                if params["threadId"].as_str() == Some(thread) =>
            {
                if method == "item/completed" && params["turnId"].as_str() == Some(turn) {
                    found_command |= command_read_marker(&params["item"], checkout, marker)?;
                } else if method == "turn/completed" && params["turn"]["id"].as_str() == Some(turn)
                {
                    checkout.revalidate()?;
                    if params["turn"]["status"] != "completed" {
                        return Err("Codex did not complete the diagnostic turn".into());
                    }
                    if !found_command {
                        return Err(
                            "the turn produced no matching successful command output".into()
                        );
                    }
                    return Ok(());
                }
            }
            ServerEvent::Request { method, params, .. }
                if params["threadId"].as_str() == Some(thread) =>
            {
                return Err(
                    format!("the default-policy probe requested interaction ({method})").into(),
                );
            }
            _ => {}
        }
    }
    Err("app-server disconnected before completing the probe turn".into())
}

fn command_read_marker(
    item: &Value,
    checkout: &CheckoutIdentity,
    marker: &str,
) -> Result<bool, ProbeError> {
    if item["type"] != "commandExecution"
        || item["status"] != "completed"
        || item["exitCode"].as_i64() != Some(0)
    {
        return Ok(false);
    }
    let cwd = item["cwd"]
        .as_str()
        .ok_or("completed command omitted its checkout")?;
    checkout.validate_reported(Path::new(cwd))?;
    Ok(item["aggregatedOutput"]
        .as_str()
        .is_some_and(|output| output.lines().any(|line| line == marker)))
}
