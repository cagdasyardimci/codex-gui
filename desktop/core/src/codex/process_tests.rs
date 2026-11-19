use std::{fs, path::Path, time::Duration};

use tempfile::tempdir;
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    time::timeout,
};
use uuid::Uuid;

use super::*;
use crate::{
    checkout::CheckoutIdentity,
    codex::fixtures::shim,
    identity::{CheckoutSessionId, ConnectionGeneration, WorkspaceIdentity},
};

const TEST_DEADLINE: Duration = Duration::from_secs(8);

#[cfg(unix)]
const SERVER: &str = "#!/bin/sh\n[ \"$3\" = app-server ] && [ \"$4\" = --stdio ] || exit 2\n[ -f .codex-fixture-checkout ] || exit 3\nprintf 'ready\\n'\nprintf 'diagnostic\\n' >&2\nIFS= read -r input && printf '%s\\n' \"$input\"\nwhile IFS= read -r input; do :; done\n";
#[cfg(windows)]
const SERVER: &str = "@echo off\r\nif not \"%~3\"==\"app-server\" exit /b 2\r\nif not \"%~4\"==\"--stdio\" exit /b 2\r\nif not exist .codex-fixture-checkout exit /b 3\r\necho ready\r\necho diagnostic 1>&2\r\nset /p input=\r\necho %input%\r\n:drain\r\nset /p input= || exit /b 0\r\ngoto drain\r\n";

fn connection(checkout: &Path, generation: u64) -> ConnectionIdentity {
    ConnectionIdentity {
        workspace: WorkspaceIdentity {
            session: CheckoutSessionId(Uuid::from_u128(1)),
            checkout: Some(CheckoutIdentity::capture(checkout).unwrap()),
        },
        generation: ConnectionGeneration(generation),
    }
}

fn fixture(directory: &Path) -> CodexExecutable {
    fs::write(directory.join(".codex-fixture-checkout"), "").unwrap();
    let shim = shim(&directory.join("fixture installation"), SERVER);
    CodexExecutable::discover(Some(&shim)).unwrap()
}

#[test]
fn spawn_rejects_a_captured_checkout_replaced_before_launch() {
    let root = tempdir().unwrap();
    let codex = fixture(root.path());
    let checkout = root.path().join("checkout");
    fs::create_dir(&checkout).unwrap();
    let captured = connection(&checkout, 1);
    fs::rename(&checkout, root.path().join("original checkout")).unwrap();
    fs::create_dir(&checkout).unwrap();

    assert!(AppServerProcess::spawn(&codex, captured).is_err());
}

#[tokio::test]
async fn stdio_remains_separate_and_closing_stdin_produces_eof_and_exit() {
    let root = tempdir().unwrap();
    let codex = fixture(root.path());
    let owner = connection(root.path(), 1);
    let mut process = AppServerProcess::spawn(&codex, owner.clone()).unwrap();
    let AppServerStdio {
        mut stdin,
        mut stdout,
        mut stderr,
    } = process.take_stdio().unwrap();
    assert!(process.take_stdio().is_none());

    let (output, diagnostics, exit) = timeout(TEST_DEADLINE, async {
        stdin.write_all(b"ping\r\n").await.unwrap();
        drop(stdin);
        let mut output = String::new();
        let mut diagnostics = String::new();
        let (_, _, exit) = tokio::try_join!(
            stdout.read_to_string(&mut output),
            stderr.read_to_string(&mut diagnostics),
            process.wait_for_exit(),
        )
        .unwrap();
        (output, diagnostics, exit)
    })
    .await
    .unwrap();

    assert_eq!(output.lines().collect::<Vec<_>>(), ["ready", "ping"]);
    assert_eq!(diagnostics.trim(), "diagnostic");
    assert_eq!(exit.connection, owner);
    assert!(exit.status.success());
}

#[tokio::test]
async fn retiring_the_old_generation_leaves_the_replacement_responsive() {
    let root = tempdir().unwrap();
    let codex = fixture(root.path());
    let old_owner = connection(root.path(), 1);
    let new_owner = connection(root.path(), 2);
    let mut old = AppServerProcess::spawn(&codex, old_owner.clone()).unwrap();
    let mut new = AppServerProcess::spawn(&codex, new_owner.clone()).unwrap();
    let old_pipes = old.take_stdio().unwrap();
    let mut new_pipes = new.take_stdio().unwrap();

    timeout(TEST_DEADLINE, async {
        let mut old_stdout = BufReader::new(old_pipes.stdout);
        let mut ready = String::new();
        old_stdout.read_line(&mut ready).await.unwrap();
        assert_eq!(ready.trim(), "ready");

        let late_exit = old.terminate().await.unwrap();
        assert_eq!(late_exit.connection, old_owner);
        assert_ne!(late_exit.connection, new_owner);

        new_pipes.stdin.write_all(b"replacement\r\n").await.unwrap();
        drop(new_pipes.stdin);
        let mut output = String::new();
        new_pipes.stdout.read_to_string(&mut output).await.unwrap();
        assert_eq!(output.lines().collect::<Vec<_>>(), ["ready", "replacement"]);

        let exit = new.wait_for_exit().await.unwrap();
        assert_eq!(exit.connection, new_owner);
        assert!(exit.status.success());
    })
    .await
    .unwrap();
}
