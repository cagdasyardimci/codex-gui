#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let beta_data = app.path().app_data_dir()?;
            std::fs::create_dir_all(beta_data.join("worktrees"))?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run Codex GUI diagnostic shell");
}
