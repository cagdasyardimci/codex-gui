use std::{collections::HashMap, fs};

use tempfile::tempdir;

use super::*;

#[cfg(unix)]
const SHIM_NAME: &str = "codex";
#[cfg(windows)]
const SHIM_NAME: &str = "codex.cmd";

fn shim(directory: &Path, contents: &str) -> PathBuf {
    fs::create_dir_all(directory).unwrap();
    let path = directory.join(SHIM_NAME);
    fs::write(&path, contents).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    path
}

fn discover(
    explicit: Option<&Path>,
    environment: &HashMap<&str, OsString>,
) -> Result<CodexExecutable, DiscoveryError> {
    CodexExecutable::discover_with(explicit, |key| environment.get(key).cloned())
}

#[test]
fn explicit_override_then_environment_override_then_path() {
    let root = tempdir().unwrap();
    let explicit = shim(&root.path().join("explicit"), "");
    let from_env = shim(&root.path().join("environment"), "");
    let from_path = shim(&root.path().join("terminal PATH"), "");
    let mut environment = HashMap::from([
        ("CODEX_EXECUTABLE", from_env.clone().into_os_string()),
        (
            "PATH",
            env::join_paths([from_path.parent().unwrap()]).unwrap(),
        ),
    ]);
    assert_eq!(
        discover(Some(&explicit), &environment).unwrap().path(),
        explicit
    );
    assert_eq!(discover(None, &environment).unwrap().path(), from_env);
    environment.remove("CODEX_EXECUTABLE");
    assert_eq!(discover(None, &environment).unwrap().path(), from_path);
}

#[test]
fn missing_explicit_override_does_not_select_another_installation() {
    let root = tempdir().unwrap();
    let missing = root.path().join("missing").join(SHIM_NAME);
    let alternative = shim(&root.path().join("fallback"), "");
    let environment = HashMap::from([(
        "PATH",
        env::join_paths([alternative.parent().unwrap()]).unwrap(),
    )]);

    assert!(matches!(
        discover(Some(&missing), &environment),
        Err(DiscoveryError::InvalidOverride(path)) if path == missing
    ));
}

#[cfg(unix)]
#[test]
fn launcher_searches_nvm_installations_in_numeric_version_order() {
    let root = tempdir().unwrap();
    let nvm = root.path().join("nvm root");
    shim(&nvm.join("versions/node/v9.0.0/bin"), "");
    let newer = shim(&nvm.join("versions/node/v10.0.0/bin"), "");
    let environment = HashMap::from([("NVM_DIR", nvm.into_os_string())]);
    let directories = launcher_directories(&|key| environment.get(key).cloned());
    let older = root.path().join("nvm root/versions/node/v9.0.0/bin");
    let newer = newer.parent().unwrap();

    let newer_position = directories.iter().position(|path| path == newer).unwrap();
    let older_position = directories.iter().position(|path| path == &older).unwrap();
    assert!(newer_position < older_position);
}

#[cfg(windows)]
#[test]
fn launcher_finds_the_roaming_npm_shim_with_a_sparse_path() {
    let root = tempdir().unwrap();
    let npm = shim(&root.path().join("roaming profile/npm"), "");
    let environment = HashMap::from([(
        "APPDATA",
        root.path().join("roaming profile").into_os_string(),
    )]);

    assert_eq!(discover(None, &environment).unwrap().path(), npm);
}

#[cfg(windows)]
#[test]
fn path_prefers_the_native_executable_over_the_batch_shim() {
    let root = tempdir().unwrap();
    shim(root.path(), "");
    let native = root.path().join("codex.exe");
    fs::write(&native, b"").unwrap();
    let environment = HashMap::from([("PATH", env::join_paths([root.path()]).unwrap())]);

    assert_eq!(discover(None, &environment).unwrap().path(), native);
}

#[tokio::test]
async fn probes_the_selected_shim_with_a_space_in_the_path() {
    #[cfg(unix)]
    let program = "#!/bin/sh\n[ \"$1\" = --version ] || exit 2\nprintf 'codex-cli 0.153.2\\n'\n";
    #[cfg(windows)]
    let program =
        "@echo off\r\nif not \"%~1\"==\"--version\" exit /b 2\r\necho codex-cli 0.153.2\r\n";
    let root = tempdir().unwrap();
    let path = shim(&root.path().join("selected installation"), program);
    let executable = discover(Some(&path), &HashMap::new()).unwrap();

    assert_eq!(
        executable
            .probe_version(Duration::from_secs(5))
            .await
            .unwrap(),
        "codex-cli 0.153.2"
    );
}

#[tokio::test]
async fn bounds_a_probe_that_never_completes() {
    #[cfg(unix)]
    let program = "#!/bin/sh\nwhile :; do :; done\n";
    #[cfg(windows)]
    let program = "@echo off\r\n:again\r\ngoto again\r\n";
    let root = tempdir().unwrap();
    let path = shim(root.path(), program);
    let executable = discover(Some(&path), &HashMap::new()).unwrap();

    assert!(matches!(
        executable.probe_version(Duration::from_millis(250)).await,
        Err(VersionProbeError::Timeout)
    ));
}

#[tokio::test]
async fn rejects_version_output_over_the_byte_limit() {
    #[cfg(unix)]
    let program = "#!/bin/sh\ni=0; while [ \"$i\" -lt 5000 ]; do printf x; i=$((i+1)); done\n";
    #[cfg(windows)]
    let program = "@echo off\r\nfor /L %%i in (1,1,5000) do @echo x\r\n";
    let root = tempdir().unwrap();
    let path = shim(root.path(), program);
    let executable = discover(Some(&path), &HashMap::new()).unwrap();

    assert!(matches!(
        executable.probe_version(Duration::from_secs(5)).await,
        Err(VersionProbeError::Oversized)
    ));
}
