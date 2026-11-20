use std::{
    ffi::OsString,
    fs, io,
    path::{Path, PathBuf},
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{
        Account, AppServerConnection, BrowserLogin, ClientInfo, CodexBrowser, CodexExecutable,
        LoginCompletion, ServerEvent,
    },
    identity::{CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, WorkspaceIdentity},
};
use serde_json::json;
use uuid::Uuid;

pub const ARGUMENT: &str = "--verify-shared-codex-profile";
const TIMEOUT: Duration = Duration::from_secs(8);
type Failure = Box<dyn std::error::Error>;

pub async fn run(arguments: impl Iterator<Item = OsString>) -> Result<(), Failure> {
    let paths = arguments.map(PathBuf::from).collect::<Vec<_>>();
    let [profile, checkout, expected_executable] = paths.as_slice() else {
        return Err("expected an isolated Codex profile, checkout and fixture CLI".into());
    };
    require(
        paths.iter().all(|path| path.is_absolute())
            && std::env::var_os("CODEX_HOME").as_deref() == Some(profile.as_os_str())
            && fs::read(profile.join(".shared-profile-fixture"))? == b"codex-gui-fixture\n",
        "the isolated fixture profile is unavailable",
    )?;
    let executable = CodexExecutable::discover(None)?;
    require(
        executable.path() == expected_executable,
        "the expected fixture CLI was not selected",
    )?;
    let owner = WorkspaceIdentity {
        session: CheckoutSessionId(Uuid::new_v4()),
        checkout: Some(CheckoutIdentity::capture(checkout)?),
    };
    let old = connect(&executable, &owner, 1, profile).await?;
    let old_client = old.client();
    let browser = CodexBrowser::new(old_client.clone());
    require(
        browser.account(TIMEOUT).await?.account.is_none(),
        "AppKit sign-out did not reach Tauri",
    )?;
    let config = browser.settings_configuration(TIMEOUT).await?;
    require(
        config.version.as_deref() == Some("fixture-high")
            && config.user_file() == Some(profile.join("config.toml").as_path()),
        "AppKit's updated user layer was not visible to Tauri",
    )?;
    let history = browser.project_chats(false, None, TIMEOUT).await?;
    require(
        history
            .data
            .iter()
            .map(|chat| chat.id.0.as_str())
            .eq(["history-first", "history-second"]),
        "the two editions did not see the same saved history",
    )?;

    fs::write(profile.join(".hold-account-read"), b"fixture\n")?;
    let delayed = tokio::spawn(async move { browser.account(TIMEOUT).await });
    let started = profile.join(".account-read-started");
    tokio::time::timeout(TIMEOUT, async {
        while !started.exists() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await?;
    old.disconnect().await?;
    require(
        delayed.await?.is_err(),
        "an account response outlived its Tauri connection",
    )?;
    fs::remove_file(profile.join(".hold-account-read"))?;
    fs::remove_file(started)?;

    let mut fresh = connect(&executable, &owner, 2, profile).await?;
    let browser = CodexBrowser::new(fresh.client());
    let BrowserLogin::Chatgpt { login_id, auth_url } = browser.begin_chatgpt_login(TIMEOUT).await?;
    require(
        auth_url == "https://example.invalid/fixture-sign-in",
        "the fixture sign-in URL changed",
    )?;
    let completion = tokio::time::timeout(TIMEOUT, async {
        while let Some(event) = fresh.next_event().await {
            if let ServerEvent::Notification { method, params } = event
                && method == "account/login/completed"
            {
                return serde_json::from_value::<LoginCompletion>(params).ok();
            }
        }
        None
    })
    .await?;
    require(
        completion
            .is_some_and(|result| result.success && result.login_id.as_deref() == Some(&login_id)),
        "the fresh sign-in did not complete for its own attempt",
    )?;
    require(
        matches!(browser.account(TIMEOUT).await?.account, Some(Account::Chatgpt { email: Some(email), .. }) if email == "tauri@example.invalid"),
        "the new fixture identity did not reach Tauri",
    )?;
    let config = browser.settings_configuration(TIMEOUT).await?;
    browser
        .write_settings_value(&config, "model_verbosity", json!("medium"), TIMEOUT)
        .await?;
    require(
        browser
            .settings_configuration(TIMEOUT)
            .await?
            .version
            .as_deref()
            == Some("fixture-medium"),
        "Tauri did not reload the effective user layer",
    )?;
    fresh.disconnect().await?;
    println!("Verified Tauri shared Codex profile and retired account read");
    Ok(())
}

async fn connect(
    executable: &CodexExecutable,
    owner: &WorkspaceIdentity,
    generation: u64,
    profile: &Path,
) -> Result<AppServerConnection, Failure> {
    let connection = AppServerConnection::connect(
        executable,
        ConnectionIdentity {
            workspace: owner.clone(),
            generation: ConnectionGeneration(generation),
        },
        ClientInfo {
            name: "codex_gui",
            title: "Codex GUI",
            version: env!("CARGO_PKG_VERSION"),
        },
        TIMEOUT,
    )
    .await?;
    let reply = connection.initialization();
    require(
        reply["userAgent"] == "structured-qa-backend/1"
            && reply["codexHome"].as_str().map(Path::new) == Some(profile),
        "the backend did not confirm the isolated fixture profile",
    )?;
    Ok(connection)
}

fn require(accepted: bool, message: &str) -> io::Result<()> {
    if accepted {
        Ok(())
    } else {
        Err(io::Error::other(message))
    }
}
