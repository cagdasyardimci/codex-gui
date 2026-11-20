#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use codex_gui_core::ipc::WORKSPACE_WINDOW;
use std::path::PathBuf;
use tauri::{Manager, RunEvent, WebviewWindowBuilder, WindowEvent, webview::NewWindowResponse};

mod coding_probe;
mod composer_context_ipc;
mod composer_ipc;
mod diff_ipc;
mod fixture;
mod navigation;
mod project_ipc;
mod quit_ipc;
mod transcript_ipc;

fn main() {
    let mut arguments = std::env::args_os().skip(1);
    let mode = arguments.next();
    if mode.as_deref() == Some(fixture::CHILD_ARGUMENT.as_ref()) {
        fixture::write_fixture().expect("write diagnostic fixture output");
        return;
    }

    let verification = match mode.as_deref().and_then(|value| value.to_str()) {
        Some("--verify-fixture") => fixture::Verification::Streaming,
        Some("--verify-media") => fixture::Verification::Media,
        Some("--verify-history") => fixture::Verification::History,
        Some("--verify-history-restore") => fixture::Verification::HistoryRestore,
        Some("--verify-attachments") => fixture::Verification::Attachments,
        Some("--verify-annotations") => fixture::Verification::Annotations,
        Some("--verify-composer-context") => fixture::Verification::ComposerContext,
        Some("--verify-composer-settings") => fixture::Verification::ComposerSettings,
        Some("--verify-project-context") => fixture::Verification::ProjectContext,
        Some("--verify-slash-commands") => fixture::Verification::SlashCommands,
        Some("--verify-prompt-revision") => fixture::Verification::PromptRevision,
        Some("--verify-conversation-fork") => fixture::Verification::ConversationFork,
        Some("--verify-account") => fixture::Verification::Account,
        Some("--verify-windows-setup") => fixture::Verification::WindowsSetup,
        Some("--verify-turn") => fixture::Verification::Turn,
        Some("--verify-active-turn") => fixture::Verification::ActiveTurn,
        Some("--verify-queue") => fixture::Verification::Queue,
        Some("--verify-diff") => fixture::Verification::Diff,
        Some("--verify-quit") => fixture::Verification::Quit,
        _ => fixture::Verification::None,
    };
    let coding_report = if mode.as_deref() == Some(coding_probe::ARGUMENT.as_ref()) {
        let target = arguments
            .next()
            .expect("expected the coding probe report path");
        Some(coding_probe::open_report(target.as_ref()).expect("create the coding probe report"))
    } else {
        None
    };
    let desktop_fixture = matches!(
        verification,
        fixture::Verification::History
            | fixture::Verification::HistoryRestore
            | fixture::Verification::Attachments
            | fixture::Verification::Annotations
            | fixture::Verification::ComposerContext
            | fixture::Verification::ComposerSettings
            | fixture::Verification::ProjectContext
            | fixture::Verification::SlashCommands
            | fixture::Verification::PromptRevision
            | fixture::Verification::ConversationFork
            | fixture::Verification::Account
            | fixture::Verification::WindowsSetup
            | fixture::Verification::Turn
            | fixture::Verification::ActiveTurn
            | fixture::Verification::Queue
            | fixture::Verification::Diff
            | fixture::Verification::Quit
    )
    .then(|| {
        let data = PathBuf::from(
            arguments
                .next()
                .expect("expected isolated application data"),
        );
        let project = arguments.next().map(PathBuf::from);
        (data, project)
    });
    let handle_desktop_quit = matches!(
        verification,
        fixture::Verification::None | fixture::Verification::Quit
    );
    let quit_fixture =
        (verification == fixture::Verification::Quit).then(|| quit_ipc::QuitFixtureCheckouts {
            primary: desktop_fixture
                .as_ref()
                .and_then(|(_, project)| project.clone()),
            secondary: arguments.next().map(PathBuf::from),
        });
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(verification)
        .manage(project_ipc::ProjectIpc::default())
        .manage(diff_ipc::DiffIpc::default())
        .manage(quit_ipc::QuitLifecycle::default())
        .on_window_event(move |window, event| {
            if handle_desktop_quit
                && window.label() == WORKSPACE_WINDOW
                && let WindowEvent::CloseRequested { api, .. } = event
                && !window.state::<quit_ipc::QuitLifecycle>().allowed()
            {
                api.prevent_close();
                quit_ipc::handle_native_quit(window.app_handle());
            }
        })
        .on_webview_event(|webview, event| {
            if webview.label() != WORKSPACE_WINDOW {
                return;
            }
            if let tauri::WebviewEvent::DragDrop(tauri::DragDropEvent::Drop { paths, .. }) = event
                && let Some(window) = webview.app_handle().get_webview_window(WORKSPACE_WINDOW)
            {
                let project = window.state::<project_ipc::ProjectIpc>();
                composer_ipc::dropped_paths(window.clone(), &project, paths.clone());
            }
        })
        .invoke_handler(tauri::generate_handler![
            fixture::stream_fixture,
            fixture::verification_mode,
            fixture::verify_fixture_result,
            fixture::verify_media_result,
            fixture::verify_history_result,
            fixture::verify_attachments_result,
            fixture::verify_account_result,
            fixture::verify_windows_setup_result,
            fixture::verify_turn_result,
            fixture::verify_diff_result,
            fixture::report_quit_failure,
            project_ipc::pick_workspace,
            project_ipc::workspace_snapshot,
            project_ipc::search_project_paths,
            composer_ipc::pick_composer_attachments,
            composer_context_ipc::composer_context_catalog,
            composer_context_ipc::read_project_context,
            composer_context_ipc::add_composer_context,
            composer_context_ipc::seed_composer_context_fixture,
            composer_ipc::paste_composer_image,
            composer_ipc::remove_composer_attachment,
            composer_ipc::load_composer_image,
            composer_ipc::read_composer_annotations,
            composer_ipc::save_composer_annotations,
            composer_ipc::reuse_composer_attachment,
            composer_ipc::drop_composer_attachment_fixture,
            transcript_ipc::copy_transcript_row,
            transcript_ipc::check_transcript_images,
            transcript_ipc::render_transcript_markdown,
            transcript_ipc::load_transcript_image,
            transcript_ipc::load_transcript_attachment,
            transcript_ipc::open_transcript_link,
            project_ipc::navigate_workspace,
            project_ipc::execute_slash_command,
            project_ipc::open_sent_prompt,
            project_ipc::subscribe_workspace,
            project_ipc::next_workspace_update,
            project_ipc::change_workspace_fixture,
            diff_ipc::checkout_changes,
            diff_ipc::checkout_patch,
            quit_ipc::request_quit_fixture,
            quit_ipc::select_quit_fixture_checkout,
        ])
        .setup(move |app| {
            if let Some(checkouts) = quit_fixture {
                app.manage(checkouts);
            }
            if let Some(report) = coding_report {
                let app = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    let code = match coding_probe::run(report).await {
                        Ok(()) => 0,
                        Err(error) => {
                            eprintln!("{error}");
                            1
                        }
                    };
                    app.exit(code);
                });
                return Ok(());
            }
            if verification == fixture::Verification::None || desktop_fixture.is_some() {
                let (beta_data, initial_project) = match desktop_fixture {
                    Some(fixture) => fixture,
                    None => (app.path().app_data_dir()?, None),
                };
                std::fs::create_dir_all(beta_data.join("worktrees"))?;
                let project = app.state::<project_ipc::ProjectIpc>();
                let navigation = navigation::NavigationHandle::start(
                    &beta_data.join("workspace.sqlite3"),
                    project.state.clone(),
                    initial_project,
                    verification,
                )
                .map_err(|error| -> Box<dyn std::error::Error> { error })?;
                assert!(project.navigation.set(navigation).is_ok());
            }
            let window = app
                .config()
                .app
                .windows
                .iter()
                .find(|window| window.label == WORKSPACE_WINDOW)
                .ok_or("missing configured main workspace window")?;
            let base = project_ipc::app_location(app.config(), window.use_https_scheme);
            WebviewWindowBuilder::from_config(app, window)?
                .on_navigation(move |url| project_ipc::allows_navigation(&base, url))
                .on_new_window(|_, _| NewWindowResponse::Deny)
                .build()?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("run Codex GUI");
    app.run(move |app, event| {
        if handle_desktop_quit
            && let RunEvent::ExitRequested { api, code, .. } = event
            && (code.is_none()
                || verification == fixture::Verification::Quit
                    && code == Some(quit_ipc::FIXTURE_APP_QUIT))
            && !app.state::<quit_ipc::QuitLifecycle>().allowed()
        {
            api.prevent_exit();
            quit_ipc::handle_native_quit(app);
        }
    });
}
