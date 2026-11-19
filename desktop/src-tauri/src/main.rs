#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

mod fixture;

fn main() {
    let mode = std::env::args_os().nth(1);
    if mode.as_deref() == Some(fixture::CHILD_ARGUMENT.as_ref()) {
        fixture::write_fixture().expect("write diagnostic fixture output");
        return;
    }

    let verifying = mode.as_deref() == Some("--verify-fixture".as_ref());
    tauri::Builder::default()
        .manage(fixture::Verification(verifying))
        .invoke_handler(tauri::generate_handler![
            fixture::stream_fixture,
            fixture::fixture_verification_enabled,
            fixture::verify_fixture_result,
        ])
        .setup(move |app| {
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
