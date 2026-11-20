#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use codex_gui_core::ipc::WORKSPACE_WINDOW;
use std::path::PathBuf;
use tauri::{Manager, RunEvent, WebviewWindowBuilder, WindowEvent, webview::NewWindowResponse};

mod coding_probe;
mod composer_context_ipc;
mod composer_ipc;
mod desktop_presentation;
mod diff_ipc;
mod file_actions_ipc;
mod file_preview_ipc;
mod file_search_ipc;
mod file_tools_ipc;
mod fixture;
mod navigation;
mod project_ipc;
mod quit_ipc;
mod settings_ipc;
mod task_notifications;
mod transcript_ipc;
mod voice_ipc;

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
        Some("--verify-sidebar") => fixture::Verification::Sidebar,
        Some("--verify-sidebar-restore") => fixture::Verification::SidebarRestore,
        Some("--verify-command-palette") => fixture::Verification::CommandPalette,
        Some("--verify-archive") => fixture::Verification::Archive,
        Some("--verify-chat-deletion") => fixture::Verification::ChatDeletion,
        Some("--verify-message-search") => fixture::Verification::MessageSearch,
        Some("--verify-automatic-titles") => fixture::Verification::AutomaticTitles,
        Some("--verify-pinned-summary") => fixture::Verification::PinnedSummary,
        Some("--verify-inspector") => fixture::Verification::Inspector,
        Some("--verify-feedback") => fixture::Verification::Feedback,
        Some("--verify-file-tools") => fixture::Verification::FileTools,
        Some("--verify-account") => fixture::Verification::Account,
        Some("--verify-settings") => fixture::Verification::Settings,
        Some("--verify-appearance") => fixture::Verification::Appearance,
        Some("--verify-appearance-restore") => fixture::Verification::AppearanceRestore,
        Some("--verify-notifications") => fixture::Verification::Notifications,
        Some("--verify-voice") => fixture::Verification::Voice,
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
            | fixture::Verification::Sidebar
            | fixture::Verification::SidebarRestore
            | fixture::Verification::CommandPalette
            | fixture::Verification::Archive
            | fixture::Verification::ChatDeletion
            | fixture::Verification::MessageSearch
            | fixture::Verification::AutomaticTitles
            | fixture::Verification::PinnedSummary
            | fixture::Verification::Inspector
            | fixture::Verification::Feedback
            | fixture::Verification::FileTools
            | fixture::Verification::Account
            | fixture::Verification::Settings
            | fixture::Verification::Appearance
            | fixture::Verification::AppearanceRestore
            | fixture::Verification::Notifications
            | fixture::Verification::Voice
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
        fixture::Verification::None
            | fixture::Verification::Quit
            | fixture::Verification::FileTools
    );
    let fixture_checkouts = matches!(
        verification,
        fixture::Verification::Quit
            | fixture::Verification::History
            | fixture::Verification::Diff
            | fixture::Verification::Settings
            | fixture::Verification::Appearance
            | fixture::Verification::AppearanceRestore
            | fixture::Verification::Notifications
            | fixture::Verification::Voice
            | fixture::Verification::FileTools
            | fixture::Verification::Sidebar
            | fixture::Verification::CommandPalette
            | fixture::Verification::ChatDeletion
    )
    .then(|| fixture::FixtureCheckouts {
        primary: desktop_fixture
            .as_ref()
            .and_then(|(_, project)| project.clone()),
        secondary: arguments.next().map(PathBuf::from),
        data: desktop_fixture.as_ref().map(|(data, _)| data.clone()),
    });
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(verification)
        .manage(project_ipc::ProjectIpc::default())
        .manage(diff_ipc::DiffIpc::default())
        .manage(settings_ipc::SettingsIpc::default())
        .manage(voice_ipc::VoiceIpc::default())
        .manage(quit_ipc::QuitLifecycle::default())
        .on_window_event(move |window, event| {
            desktop_presentation::on_window_event(window, event);
            if handle_desktop_quit
                && window.label() == WORKSPACE_WINDOW
                && let WindowEvent::CloseRequested { api, .. } = event
                && !window.state::<quit_ipc::QuitLifecycle>().allowed()
            {
                api.prevent_close();
                quit_ipc::handle_native_quit(window.app_handle());
            }
        })
        .on_menu_event(|app, event| {
            if let Some(window) = app.get_webview_window(WORKSPACE_WINDOW)
                && let Err(error) =
                    desktop_presentation::window::dispatch_menu(&window, event.id().as_ref())
            {
                eprintln!("{error:?}");
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
            fixture::set_settings_fixture_profile,
            fixture::set_settings_reset_fixture,
            fixture::settings_usage_fixture_started,
            fixture::external_settings_instructions_fixture,
            fixture::verify_windows_setup_result,
            fixture::verify_turn_result,
            fixture::verify_diff_result,
            fixture::change_compared_file_fixture,
            fixture::report_quit_failure,
            fixture::overwrite_file_tools_fixture,
            fixture::file_save_fixture_gate,
            project_ipc::pick_workspace,
            project_ipc::workspace_snapshot,
            settings_ipc::open_settings,
            settings_ipc::refresh_settings,
            settings_ipc::close_settings,
            settings_ipc::sign_out_settings,
            settings_ipc::writes::write_settings,
            settings_ipc::writes::set_effort_visibility,
            settings_ipc::writes::delete_settings_memories,
            settings_ipc::usage_resets::redeem_settings_reset,
            settings_ipc::integrations::read_settings_catalog,
            settings_ipc::integrations::read_settings_mcp,
            settings_ipc::integrations::change_settings_integration,
            settings_ipc::instructions::read_settings_instructions,
            settings_ipc::instructions::save_settings_instructions,
            desktop_presentation::read_desktop_appearance,
            desktop_presentation::desktop_font_families,
            desktop_presentation::update_desktop_appearance,
            desktop_presentation::copy_desktop_theme,
            desktop_presentation::export_desktop_theme,
            desktop_presentation::appearance_fixture_action,
            desktop_presentation::appearance_fixture_state,
            desktop_presentation::verify_appearance_result,
            task_notifications::read_notification_preferences,
            task_notifications::update_notification_preferences,
            task_notifications::request_notification_permission,
            task_notifications::import_notification_sound,
            task_notifications::configure_notification_fixture,
            task_notifications::choose_notification_fixture_sound,
            task_notifications::notification_fixture_outcomes,
            task_notifications::activate_notification_fixture,
            task_notifications::verify_notifications_result,
            voice_ipc::read_voice_call,
            voice_ipc::prepare_voice_call,
            voice_ipc::start_voice_transport,
            voice_ipc::voice_media_ready,
            voice_ipc::set_voice_mute,
            voice_ipc::end_voice_call,
            voice_ipc::record_voice_fixture_exchange,
            voice_ipc::read_voice_fixture_media,
            voice_ipc::verify_voice_result,
            project_ipc::search_project_paths,
            file_tools_ipc::change_file_tools,
            file_tools_ipc::browse_project_files,
            file_tools_ipc::read_file_tab,
            file_preview_ipc::read_file_preview,
            file_tools_ipc::edit_file_tab,
            file_tools_ipc::save_file_tab,
            file_actions_ipc::file_tab_actions,
            file_actions_ipc::perform_file_action,
            file_actions_ipc::render_file_markdown,
            file_actions_ipc::file_markdown_image,
            file_actions_ipc::export_file_markdown_image,
            file_actions_ipc::export_file_image,
            file_actions_ipc::save_preview_image,
            file_actions_ipc::open_file_markdown_link,
            file_search_ipc::start_file_search,
            file_search_ipc::read_file_search,
            file_search_ipc::cancel_file_search,
            file_search_ipc::open_file_search_hit,
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
            transcript_ipc::reveal_inspector_attachment,
            project_ipc::navigate_workspace,
            project_ipc::read_archive,
            project_ipc::prepare_chat_deletion,
            project_ipc::open_message_search,
            project_ipc::read_message_search_page,
            project_ipc::open_inspector_source,
            project_ipc::read_inspector_source_detail,
            project_ipc::read_child_history,
            project_ipc::execute_slash_command,
            project_ipc::open_sent_prompt,
            project_ipc::reveal_sidebar_project,
            project_ipc::subscribe_workspace,
            project_ipc::next_workspace_update,
            project_ipc::change_workspace_fixture,
            diff_ipc::checkout_changes,
            diff_ipc::close_checkout_changes,
            diff_ipc::count_chat_changes,
            diff_ipc::checkout_patch,
            diff_ipc::checkout_diff_references,
            diff_ipc::mark_checkout_change,
            diff_ipc::actions::checkout_diff_media,
            diff_ipc::actions::checkout_diff_markdown,
            diff_ipc::actions::checkout_diff_action,
            quit_ipc::request_quit_fixture,
            fixture::select_fixture_checkout,
            fixture::seed_deletion_fixture,
        ])
        .setup(move |app| {
            if let Some(checkouts) = fixture_checkouts {
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
            let desktop = verification == fixture::Verification::None || desktop_fixture.is_some();
            let presentation = if desktop {
                let (beta_data, initial_project) = match desktop_fixture {
                    Some(fixture) => fixture,
                    None => (app.path().app_data_dir()?, None),
                };
                std::fs::create_dir_all(beta_data.join("worktrees"))?;
                app.manage(task_notifications::TaskNotifications::open(
                    Some(&beta_data),
                    verification,
                ));
                let project = app.state::<project_ipc::ProjectIpc>();
                let navigation = navigation::NavigationHandle::start(
                    app.handle().clone(),
                    &beta_data.join("workspace.sqlite3"),
                    project.state.clone(),
                    initial_project,
                    verification,
                )
                .map_err(|error| -> Box<dyn std::error::Error> { error })?;
                assert!(project.navigation.set(navigation).is_ok());
                desktop_presentation::DesktopPresentation::open(Some(&beta_data))
            } else {
                app.manage(task_notifications::TaskNotifications::open(
                    None,
                    verification,
                ));
                desktop_presentation::DesktopPresentation::open(None)
            };
            let theme = presentation.initial_theme();
            app.manage(presentation);
            if desktop {
                app.set_menu(desktop_presentation::window::menu(app.handle())?)?;
            }
            let window = app
                .config()
                .app
                .windows
                .iter()
                .find(|window| window.label == WORKSPACE_WINDOW)
                .ok_or("missing configured main workspace window")?;
            let base = project_ipc::app_location(app.config(), window.use_https_scheme);
            let window = WebviewWindowBuilder::from_config(app, window)?
                .theme(theme)
                .visible(false)
                .on_navigation(move |url| project_ipc::allows_navigation(&base, url))
                .on_new_window(|_, _| NewWindowResponse::Deny)
                .build()?;
            window
                .state::<desktop_presentation::DesktopPresentation>()
                .initialize_window(&window);
            window.show()?;
            if desktop && let Err(error) = window.set_focus() {
                eprintln!("{error}");
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("run Codex GUI");
    app.run(move |app, event| {
        if handle_desktop_quit
            && let RunEvent::ExitRequested { api, code, .. } = event
            && (code.is_none()
                || matches!(
                    verification,
                    fixture::Verification::Quit | fixture::Verification::FileTools
                ) && code == Some(quit_ipc::FIXTURE_APP_QUIT))
            && !app.state::<quit_ipc::QuitLifecycle>().allowed()
        {
            api.prevent_exit();
            quit_ipc::handle_native_quit(app);
        }
    });
}
