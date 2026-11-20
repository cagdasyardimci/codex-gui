fn main() {
    let commands = tauri_build::AppManifest::new().commands(&[
        "stream_fixture",
        "verification_mode",
        "verify_fixture_result",
        "verify_media_result",
        "verify_history_result",
        "verify_account_result",
        "verify_windows_setup_result",
        "pick_workspace",
        "workspace_snapshot",
        "navigate_workspace",
        "subscribe_workspace",
        "next_workspace_update",
        "change_workspace_fixture",
    ]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(commands))
        .expect("build Tauri application");
}
