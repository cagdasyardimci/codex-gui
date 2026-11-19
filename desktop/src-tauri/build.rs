fn main() {
    let commands = tauri_build::AppManifest::new().commands(&[
        "stream_fixture",
        "fixture_verification_enabled",
        "verify_fixture_result",
    ]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(commands))
        .expect("build Tauri application");
}
