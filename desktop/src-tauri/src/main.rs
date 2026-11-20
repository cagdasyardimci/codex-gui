#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use codex_gui_core::ipc::WORKSPACE_WINDOW;
use tauri::{Manager, WebviewWindowBuilder, webview::NewWindowResponse};

mod coding_probe;
mod fixture;
mod project_ipc;

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
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(verification)
        .manage(project_ipc::ProjectIpc::default())
        .invoke_handler(tauri::generate_handler![
            fixture::stream_fixture,
            fixture::verification_mode,
            fixture::verify_fixture_result,
            fixture::verify_media_result,
            project_ipc::pick_workspace,
            project_ipc::workspace_snapshot,
        ])
        .setup(move |app| {
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
            if verification != fixture::Verification::None {
                return Ok(());
            }
            let beta_data = app.path().app_data_dir()?;
            std::fs::create_dir_all(beta_data.join("worktrees"))?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run Codex GUI");
}
