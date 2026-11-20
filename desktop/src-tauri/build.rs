fn main() {
    let commands = tauri_build::AppManifest::new().commands(&[
        "stream_fixture",
        "verification_mode",
        "verify_fixture_result",
        "verify_media_result",
        "pick_workspace",
        "workspace_snapshot",
    ]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(commands))
        .expect("build Tauri application");
}
