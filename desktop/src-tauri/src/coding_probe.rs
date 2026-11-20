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
const UNIX_READ: &str = "/bin/cat -- ./codex-gui-probe.txt";
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
    let prompt = if cfg!(target_os = "linux") {
        format!(
            "Run exactly this local shell command in the current checkout, then report completion: {UNIX_READ}"
        )
    } else {
        format!(
            "Use a local shell command to read {MARKER_FILE} in this checkout. Print the contents to command output and report completion."
        )
    };
    let outcome = async {
        let reply = client
            .request(
                "turn/start",
                json!({
                    "threadId": thread,
                    "cwd": checkout_path,
                    "clientUserMessageId": Uuid::new_v4().to_string(),
                    "input": [{
                        "type": "text",
                        "text": prompt,
                    }],
                }),
                RPC_TIMEOUT,
            )
            .await?;
        let turn = reply["turn"]["id"]
            .as_str()
            .filter(|id| !id.is_empty())
            .ok_or("Codex did not assign a turn ID")?;
        timeout(
            TURN_TIMEOUT,
            observe_turn(&mut connection, &checkout, &thread, turn, &marker),
        )
        .await?
    }
    .await;

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
    let mut approved_probe_read = false;
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
            ServerEvent::Request { id, method, params }
                if params["threadId"].as_str() == Some(thread) =>
            {
                if approved_probe_read
                    || method != "item/commandExecution/requestApproval"
                    || params["turnId"].as_str() != Some(turn)
                    || !permits_probe_read(&params, checkout, marker)?
                {
                    return Err(format!(
                        "the coding probe received an unexpected interaction ({method})"
                    )
                    .into());
                }
                connection
                    .client()
                    .respond(&id, json!({"decision": "accept"}), RPC_TIMEOUT)
                    .await?;
                approved_probe_read = true;
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

fn permits_probe_read(
    params: &Value,
    checkout: &CheckoutIdentity,
    marker: &str,
) -> Result<bool, ProbeError> {
    if !cfg!(unix)
        || !params["kind"].is_null() && params["kind"] != "command"
        || !params["networkApprovalContext"].is_null()
        || !params["additionalPermissions"].is_null()
        || params["availableDecisions"]
            .as_array()
            .is_some_and(|decisions| !decisions.iter().any(|decision| decision == "accept"))
    {
        return Ok(false);
    }
    let Some(command) = params["command"].as_str().and_then(shlex::split) else {
        return Ok(false);
    };
    let command: Vec<_> = command.iter().map(String::as_str).collect();
    if !matches!(
        command.as_slice(),
        ["/bin/cat", "--", "./codex-gui-probe.txt"]
            | [
                "/bin/bash" | "/usr/bin/bash" | "/bin/sh" | "/usr/bin/sh",
                "-c" | "-lc",
                UNIX_READ
            ]
    ) {
        return Ok(false);
    }
    let cwd = params["cwd"]
        .as_str()
        .ok_or("probe approval omitted its checkout")?;
    checkout.validate_reported(Path::new(cwd))?;
    let marker_path = checkout.canonical_path().join(MARKER_FILE);
    let metadata = fs::symlink_metadata(&marker_path)?;
    Ok(metadata.is_file()
        && metadata.len() == (marker.len() + 1) as u64
        && fs::read_to_string(marker_path)? == format!("{marker}\n"))
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn diagnostic_approval_is_limited_to_the_literal_marker_read() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join(MARKER_FILE), "probe\n").unwrap();
        let checkout = CheckoutIdentity::capture(workspace.path()).unwrap();
        let request = json!({
            "cwd": checkout.canonical_path(),
            "kind": "command",
            "command": "/bin/bash -lc '/bin/cat -- ./codex-gui-probe.txt'",
        });
        assert!(permits_probe_read(&request, &checkout, "probe").unwrap());

        let mut chained = request.clone();
        chained["command"] = json!("/bin/bash -lc '/bin/cat -- ./codex-gui-probe.txt; pwd'");
        assert!(!permits_probe_read(&chained, &checkout, "probe").unwrap());

        let mut network = request.clone();
        network["networkApprovalContext"] = json!({"host": "example.invalid"});
        assert!(!permits_probe_read(&network, &checkout, "probe").unwrap());

        let foreign = tempfile::tempdir().unwrap();
        let mut other_checkout = request;
        other_checkout["cwd"] = json!(foreign.path());
        assert!(permits_probe_read(&other_checkout, &checkout, "probe").is_err());
    }
}
