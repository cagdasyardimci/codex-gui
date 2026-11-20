use std::{
    env,
    io::{self, Write},
    path::PathBuf,
    process::Stdio,
    time::Duration,
};

use codex_gui_core::codex::{JsonlReader, ServerEvent, ServerMessage, read_message};
use codex_gui_core::ipc::{
    IpcError, StreamChange, TextBatcher, TranscriptItem, TranscriptRole, WorkspaceId,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tauri::{AppHandle, Manager, State, WebviewWindow};
use tokio::{process::Command, time::MissedTickBehavior};

use crate::project_ipc::{ProjectIpc, authorize_view};

pub const CHILD_ARGUMENT: &str = "--diagnostic-fixture-stdio";
const STREAMING_SCENARIO: &str =
    include_str!("../../../Tests/E2E/MockBackend/mock_backend/scenarios/streaming.json");
const PRIMARY_ITEM: &str = "fixture-main-item";
const SECONDARY_ITEM: &str = "fixture-secondary-item";
const SECONDARY_TEXT: [&str; 2] = ["cafe\u{301} ", "漢字 👩🏽‍💻"];

#[derive(Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Verification {
    None,
    Streaming,
    Media,
    History,
    HistoryRestore,
    Attachments,
    Annotations,
    ComposerContext,
    ComposerSettings,
    ProjectContext,
    SlashCommands,
    PromptRevision,
    ConversationFork,
    Sidebar,
    SidebarRestore,
    CommandPalette,
    Archive,
    ChatDeletion,
    MessageSearch,
    AutomaticTitles,
    PinnedSummary,
    Inspector,
    Feedback,
    FileTools,
    Account,
    Settings,
    WindowsSetup,
    Turn,
    ActiveTurn,
    Queue,
    Diff,
    Quit,
}

pub struct FixtureCheckouts {
    pub primary: Option<PathBuf>,
    pub secondary: Option<PathBuf>,
    pub data: Option<PathBuf>,
}

#[tauri::command]
pub async fn select_fixture_checkout(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
    secondary: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if !matches!(
        *verification,
        Verification::Quit
            | Verification::Sidebar
            | Verification::CommandPalette
            | Verification::ChatDeletion
    ) {
        return Err(IpcError::UnauthorizedWindow);
    }
    let path = if secondary {
        &checkouts.secondary
    } else {
        &checkouts.primary
    };
    let path = path.clone().ok_or(IpcError::InvalidCheckout)?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.select(path).await?;
    Ok(())
}

#[tauri::command]
pub async fn seed_deletion_fixture(
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
) -> Result<(), IpcError> {
    use codex_gui_core::{
        checkout::CheckoutIdentity,
        worktree::{WorktreeManager, WorktreeStore},
    };

    authorize_view(&window)?;
    if *verification != Verification::ChatDeletion {
        return Err(IpcError::UnauthorizedWindow);
    }
    let data = checkouts.data.as_ref().ok_or(IpcError::InvalidCheckout)?;
    let primary = checkouts
        .primary
        .as_ref()
        .ok_or(IpcError::InvalidCheckout)?;
    let perform = async {
        let root = data.join("managed");
        std::fs::create_dir_all(&root)?;
        let store = WorktreeStore::initialize_tauri(&data.join("worktrees"))?;
        let manager = WorktreeManager::new(store, CheckoutIdentity::capture(&root)?);
        let checkout = manager
            .create(
                CheckoutIdentity::capture(primary)?,
                "managed-chat",
                "Managed fixture",
            )
            .await?;
        let bound = manager
            .bind(checkout.id, "managed-chat", &checkout.checkout_path)
            .await?;
        std::fs::write(
            bound.checkout_path.join("keep-local.txt"),
            b"Local work must survive chat deletion.",
        )?;
        Ok::<_, Box<dyn std::error::Error + Send + Sync>>(bound.checkout_path)
    };
    let path = perform.await.map_err(|error| {
        eprintln!("{error}");
        IpcError::ProjectUnavailable
    })?;
    let navigation = state.navigation.get().ok_or(IpcError::ProjectUnavailable)?;
    navigation.select(path).await?;
    Ok(())
}

#[derive(Deserialize)]
struct Scenario {
    chunks: Vec<String>,
}

fn scenario() -> serde_json::Result<Scenario> {
    serde_json::from_str(STREAMING_SCENARIO)
}

pub fn write_fixture() -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    for (group, chunks) in scenario()?.chunks.chunks(4).enumerate() {
        let mut burst = Vec::new();
        for (index, text) in chunks.iter().enumerate() {
            write_notification(
                &mut burst,
                "item/agentMessage/delta",
                json!({"itemId": PRIMARY_ITEM, "delta": text}),
            )?;
            if group == 0
                && let Some(text) = SECONDARY_TEXT.get(index)
            {
                write_notification(
                    &mut burst,
                    "item/agentMessage/delta",
                    json!({"itemId": SECONDARY_ITEM, "delta": text}),
                )?;
            }
        }
        if group == 0 {
            write_notification(
                &mut burst,
                "item/completed",
                json!({"item": {"id": SECONDARY_ITEM}}),
            )?;
        }
        stdout.write_all(&burst)?;
        stdout.flush()?;
        std::thread::sleep(Duration::from_millis(75));
    }
    write_notification(
        &mut stdout,
        "item/completed",
        json!({"item": {"id": PRIMARY_ITEM}}),
    )?;
    write_notification(&mut stdout, "turn/completed", json!({}))?;
    stdout.flush()?;
    Ok(())
}

fn write_notification(mut output: impl Write, method: &str, params: Value) -> io::Result<()> {
    serde_json::to_writer(&mut output, &json!({"method": method, "params": params}))?;
    output.write_all(b"\n")
}

#[tauri::command]
pub async fn stream_fixture(
    app: AppHandle,
    window: WebviewWindow,
    state: State<'_, ProjectIpc>,
    verification: State<'_, Verification>,
) -> Result<bool, String> {
    if *verification != Verification::Streaming {
        return Err("fixture verification was not requested at launch".into());
    }
    let Some(workspace) = state
        .start_fixture(&window)
        .map_err(|error| format!("{error:?}"))?
    else {
        return Ok(false);
    };
    tauri::async_runtime::spawn(async move {
        match tokio::time::timeout(
            Duration::from_secs(15),
            send_fixture(&app.state::<ProjectIpc>(), workspace),
        )
        .await
        {
            Ok(Ok(())) => return,
            Ok(Err(error)) => eprintln!("{error}"),
            Err(_) => eprintln!("stream fixture timed out"),
        }
        app.exit(1);
    });
    Ok(true)
}

async fn send_fixture(
    state: &ProjectIpc,
    workspace: WorkspaceId,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut command = Command::new(env::current_exe()?);
    command
        .arg(CHILD_ARGUMENT)
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stdout(Stdio::piped());
    #[cfg(windows)]
    {
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command.spawn()?;
    let stdout = child.stdout.take().expect("fixture stdout is piped");
    let mut reader = JsonlReader::new(stdout, 64 * 1024);
    let mut timer = tokio::time::interval(Duration::from_millis(20));
    timer.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut batcher = TextBatcher::default();
    let mut input_deltas = 0;
    let mut published_batches = 0;
    let mut turn_finished = false;
    let mut publish = |change: StreamChange| {
        if matches!(&change, StreamChange::Text(_)) {
            published_batches += 1;
        }
        state
            .publish_stream(workspace, change)
            .then_some(())
            .ok_or("fixture stream lost its workspace")
    };
    loop {
        let message = tokio::select! {
            biased;
            _ = timer.tick() => {
                if let Some(batch) = batcher.flush() {
                    publish(batch)?;
                }
                continue;
            }
            message = read_message(&mut reader) => message?,
        };
        let Some(message) = message else { break };
        if turn_finished {
            return Err("fixture sent a notification after turn completion".into());
        }
        let ServerMessage::Event(ServerEvent::Notification { method, params }) = message else {
            return Err("fixture sent an unexpected envelope".into());
        };
        match method.as_str() {
            "item/agentMessage/delta" => {
                let id = params["itemId"]
                    .as_str()
                    .ok_or("invalid fixture item identity")?;
                let text = params["delta"].as_str().ok_or("invalid fixture delta")?;
                input_deltas += 1;
                if let Some(batch) = batcher.append(id.to_owned(), text.to_owned()) {
                    publish(batch)?;
                }
            }
            "item/completed" => {
                let id = params["item"]["id"]
                    .as_str()
                    .ok_or("invalid fixture item identity")?;
                for change in batcher.finish(StreamChange::ItemCompleted(id.to_owned())) {
                    publish(change)?;
                }
            }
            "turn/completed" => turn_finished = true,
            _ => return Err("fixture sent an unexpected notification".into()),
        }
    }
    if !turn_finished || !child.wait().await?.success() {
        return Err("fixture child did not complete the stream".into());
    }
    if let Some(batch) = batcher.flush() {
        publish(batch)?;
    }
    if published_batches >= input_deltas {
        return Err("fixture did not coalesce stream text".into());
    }
    if !state.publish_stream(workspace, StreamChange::Completed) {
        return Err("fixture stream lost its workspace".into());
    }
    Ok(())
}

#[tauri::command]
pub fn verification_mode(verification: State<'_, Verification>) -> Verification {
    *verification
}

#[tauri::command]
pub fn verify_history_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if !matches!(
        *verification,
        Verification::History | Verification::HistoryRestore
    ) {
        return Err("history verification was not requested at launch".into());
    }
    if let Some(failure) = failure {
        eprintln!("History verification failed: {failure}");
        app.exit(1);
    } else {
        println!("Verified installed project history, drafts, streaming, and writer recovery");
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn verify_attachments_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if !matches!(
        *verification,
        Verification::Attachments
            | Verification::Annotations
            | Verification::ComposerContext
            | Verification::ComposerSettings
            | Verification::ProjectContext
            | Verification::SlashCommands
            | Verification::PromptRevision
            | Verification::ConversationFork
            | Verification::Sidebar
            | Verification::SidebarRestore
            | Verification::CommandPalette
            | Verification::Archive
            | Verification::ChatDeletion
            | Verification::MessageSearch
            | Verification::AutomaticTitles
            | Verification::PinnedSummary
            | Verification::Inspector
            | Verification::Feedback
    ) {
        return Err("attachment verification was not requested".into());
    }
    if let Some(failure) = failure {
        eprintln!("Attachment verification failed: {failure}");
        app.exit(1);
    } else {
        if *verification == Verification::Annotations {
            println!(
                "Verified installed image annotation placement, cancellation, and restoration"
            );
        } else if *verification == Verification::ComposerContext {
            println!(
                "Verified installed composer context, token replacement, and captured ownership"
            );
        } else if *verification == Verification::ComposerSettings {
            println!("Verified installed composer settings and captured permission confirmation");
        } else if *verification == Verification::ProjectContext {
            println!(
                "Verified installed Project Context, defaults, saved prompts, and bookmark ownership"
            );
        } else if *verification == Verification::SlashCommands {
            println!(
                "Verified installed slash commands, context usage, compaction, and plan recovery"
            );
        } else if *verification == Verification::PromptRevision {
            println!("Verified installed sent prompt revisions and retained fork drafts");
        } else if *verification == Verification::ConversationFork {
            println!(
                "Verified installed response branches, saved bookmarks, and writer-locked forks"
            );
        } else if matches!(
            *verification,
            Verification::Sidebar | Verification::SidebarRestore
        ) {
            println!("Verified installed sidebar projects, scoped chats, and saved organization");
        } else if *verification == Verification::CommandPalette {
            println!("Verified installed keyboard command palette and scoped choosers");
        } else if *verification == Verification::Archive {
            println!("Verified installed project and chat archive, restore, and search");
        } else if *verification == Verification::ChatDeletion {
            println!("Verified installed scoped permanent chat deletion");
        } else if *verification == Verification::MessageSearch {
            println!("Verified installed incremental paged message search");
        } else if *verification == Verification::AutomaticTitles {
            println!("Verified installed scoped automatic chat titles");
        } else if *verification == Verification::PinnedSummary {
            println!("Verified installed scoped pinned chat summaries");
        } else if *verification == Verification::Inspector {
            println!("Verified installed scoped conversation inspectors");
        } else if *verification == Verification::Feedback {
            println!("Verified installed scoped turn feedback");
        } else {
            println!("Verified installed draft attachment capture, ownership, Send, and reuse");
        }
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn verify_account_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if !matches!(
        *verification,
        Verification::Account | Verification::Settings
    ) {
        return Err("account verification was not requested at launch".into());
    }
    if let Some(failure) = failure {
        eprintln!("Account verification failed: {failure}");
        app.exit(1);
    } else if *verification == Verification::Settings {
        println!("Verified installed account, usage, configuration, and settings-owned sign-out");
        app.exit(0);
    } else {
        println!("Verified installed ChatGPT sign-in, cancellation, and connection-scoped refresh");
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn set_settings_fixture_profile(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
    profile: String,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Settings
        || !matches!(profile.as_str(), "first" | "second" | "bedrock" | "delayed")
    {
        return Err(IpcError::UnauthorizedWindow);
    }
    let path = checkouts
        .data
        .as_ref()
        .ok_or(IpcError::UnauthorizedWindow)?
        .join("fixture-account.json");
    let stage = path.with_extension("profile");
    std::fs::write(&stage, json!({"profile": profile}).to_string())
        .and_then(|()| std::fs::rename(stage, path))
        .map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub fn settings_usage_fixture_started(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
) -> Result<bool, IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Settings {
        return Err(IpcError::UnauthorizedWindow);
    }
    let data = checkouts
        .data
        .as_ref()
        .ok_or(IpcError::UnauthorizedWindow)?;
    Ok(data.join("settings-usage-started").exists())
}

#[tauri::command]
pub fn external_settings_instructions_fixture(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Settings {
        return Err(IpcError::UnauthorizedWindow);
    }
    let root = checkouts
        .data
        .as_ref()
        .and_then(|path| path.parent())
        .ok_or(IpcError::UnauthorizedWindow)?;
    std::fs::write(
        root.join("isolated Codex profile").join("AGENTS.md"),
        b"\xef\xbb\xbfExternal instructions\r\nReview the next draft.\r\n",
    )
    .map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub fn verify_windows_setup_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if *verification != Verification::WindowsSetup {
        return Err("Windows setup verification was not requested at launch".into());
    }
    if let Some(failure) = failure {
        eprintln!("Windows setup verification failed: {failure}");
        app.exit(1);
    } else {
        println!("Verified installed Windows sandbox setup and draft retention");
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn verify_turn_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if !matches!(
        *verification,
        Verification::Turn | Verification::ActiveTurn | Verification::Queue
    ) {
        return Err("turn verification was not requested at launch".into());
    }
    if let Some(failure) = failure {
        eprintln!("Turn verification failed: {failure}");
        app.exit(1);
    } else {
        if *verification == Verification::Turn {
            println!("Verified installed Send, recovery, approval, questions, and Git patch");
        } else if *verification == Verification::ActiveTurn {
            println!("Verified installed active-turn Stop after chat switch and reload");
        } else {
            println!(
                "Verified installed queue controls, captured routing, and preference after reload"
            );
        }
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn verify_diff_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: Option<String>,
) -> Result<(), String> {
    if *verification != Verification::Diff {
        return Err("diff verification was not requested at launch".into());
    }
    if let Some(failure) = failure {
        eprintln!("Diff verification failed: {failure}");
        app.exit(1);
    } else {
        println!("Verified installed checkout changes and lazy patches");
        app.exit(0);
    }
    Ok(())
}

#[tauri::command]
pub fn change_compared_file_fixture(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
    restore: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Diff {
        return Err(IpcError::UnauthorizedWindow);
    }
    let root = checkouts
        .primary
        .as_ref()
        .ok_or(IpcError::InvalidCheckout)?;
    let target = root.join("notes café [draft].txt");
    let held = checkouts
        .data
        .as_ref()
        .ok_or(IpcError::ProjectUnavailable)?
        .join("diff-fixture-next-revision");
    let result = if restore {
        std::fs::rename(held, target)
    } else {
        std::fs::read_to_string(&target).and_then(|prior| {
            std::fs::write(held, prior.replace("After 日本語", "External revision"))?;
            std::fs::remove_file(target)
        })
    };
    result.map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub fn report_quit_failure(
    app: AppHandle,
    verification: State<'_, Verification>,
    failure: String,
) -> Result<(), String> {
    if !matches!(*verification, Verification::Quit | Verification::FileTools) {
        return Err("quit verification was not requested at launch".into());
    }
    eprintln!("Quit verification failed: {failure}");
    app.exit(1);
    Ok(())
}

#[tauri::command]
pub fn overwrite_file_tools_fixture(
    window: tauri::WebviewWindow,
    verification: State<'_, Verification>,
    checkouts: State<'_, FixtureCheckouts>,
    replacement: Option<bool>,
) -> Result<(), IpcError> {
    crate::project_ipc::authorize_view(&window)?;
    if *verification != Verification::FileTools {
        return Err(IpcError::UnauthorizedWindow);
    }
    let root = checkouts
        .primary
        .as_ref()
        .ok_or(IpcError::InvalidCheckout)?;
    let result = if replacement == Some(true) {
        let path = root.join("replace.txt");
        std::fs::read(&path).and_then(|bytes| {
            std::fs::rename(&path, root.join("retired-search.txt"))?;
            std::fs::write(path, bytes)
        })
    } else {
        std::fs::write(root.join("conflict.txt"), b"An external change\n")
    };
    result.map_err(|_| IpcError::ProjectUnavailable)
}

#[tauri::command]
pub fn file_save_fixture_gate(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    project: State<'_, ProjectIpc>,
    hold: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::FileTools {
        return Err(IpcError::UnauthorizedWindow);
    }
    let mut model = project.state.lock().expect("workspace state lock poisoned");
    if hold {
        if model.file_save_fixture_gate.is_some() {
            return Err(IpcError::StaleSelection);
        }
        model.file_save_fixture_gate = Some(std::sync::Arc::new(tokio::sync::Semaphore::new(0)));
    } else {
        model
            .file_save_fixture_gate
            .take()
            .ok_or(IpcError::StaleSelection)?
            .add_permits(1);
    }
    Ok(())
}

#[tauri::command]
pub fn verify_fixture_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    scope_verified: bool,
    subscription_verified: bool,
    stream_recovered: bool,
    items: Vec<TranscriptItem>,
    rendered: String,
) -> Result<(), String> {
    if *verification != Verification::Streaming {
        return Err("fixture verification was not requested at launch".into());
    }
    if !scope_verified {
        eprintln!("Workspace IPC did not return the expected error for an unknown grant");
        app.exit(1);
        return Ok(());
    }
    if !subscription_verified {
        eprintln!(
            "Workspace subscription did not recover the complete revision after a gap and reload"
        );
        app.exit(1);
        return Ok(());
    }
    let chunks = scenario().map_err(|error| error.to_string())?.chunks;
    let expected = [
        (PRIMARY_ITEM, chunks.concat()),
        (SECONDARY_ITEM, SECONDARY_TEXT.concat()),
    ];
    let expected_text: String = expected.iter().map(|(_, text)| text.as_str()).collect();
    let exact_rows = items.len() == expected.len()
        && items.iter().zip(&expected).all(|(item, (id, text))| {
            item.item_id == *id
                && item.text == *text
                && item.completed
                && item.role == TranscriptRole::Assistant
                && item.revision > 0
        });
    if !stream_recovered || !exact_rows || rendered != expected_text {
        eprintln!("WebView fixture differed from the expected ordered Unicode output");
        app.exit(1);
        return Ok(());
    }
    println!("Verified workspace grant rejection and revision recovery across WebView reload");
    println!(
        "Verified {} ordered fixture deltas and exact WebView text",
        chunks.len() + SECONDARY_TEXT.len()
    );
    println!(
        "Verified item batching, terminal ordering, and exact transcript recovery across reconnect"
    );
    app.exit(0);
    Ok(())
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaEvidence {
    secure_context: bool,
    capture_api: bool,
    playback_api: bool,
    peer_api: bool,
    negotiated_sessions: u8,
    failure: Option<String>,
}

#[tauri::command]
pub fn verify_media_result(
    app: AppHandle,
    verification: State<'_, Verification>,
    evidence: MediaEvidence,
) -> Result<(), String> {
    if *verification != Verification::Media {
        return Err("media verification was not requested at launch".into());
    }
    let negotiation = if evidence.peer_api {
        evidence.negotiated_sessions == 2
    } else {
        cfg!(target_os = "linux") && evidence.negotiated_sessions == 0
    };
    let passed = evidence.secure_context
        && evidence.capture_api
        && evidence.playback_api
        && evidence.failure.is_none()
        && negotiation;
    println!("WebView media evidence: {}", json!(evidence));
    app.exit(i32::from(!passed));
    Ok(())
}
