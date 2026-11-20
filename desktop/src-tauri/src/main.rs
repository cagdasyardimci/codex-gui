#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

mod coding_probe;
mod fixture;

fn main() {
    let mut arguments = std::env::args_os().skip(1);
    let mode = arguments.next();
    if mode.as_deref() == Some(fixture::CHILD_ARGUMENT.as_ref()) {
        fixture::write_fixture().expect("write diagnostic fixture output");
        return;
    }

    let verifying = mode.as_deref() == Some("--verify-fixture".as_ref());
    let coding_report = if mode.as_deref() == Some(coding_probe::ARGUMENT.as_ref()) {
        let target = arguments
            .next()
            .expect("expected the coding probe report path");
        Some(coding_probe::open_report(target.as_ref()).expect("create the coding probe report"))
    } else {
        None
    };
    tauri::Builder::default()
        .manage(fixture::Verification(verifying))
        .invoke_handler(tauri::generate_handler![
            fixture::stream_fixture,
            fixture::fixture_verification_enabled,
            fixture::verify_fixture_result,
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
            if verifying {
                return Ok(());
            }
            let beta_data = app.path().app_data_dir()?;
            std::fs::create_dir_all(beta_data.join("worktrees"))?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run Codex GUI diagnostic shell");
}
