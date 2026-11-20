use std::{
    ffi::OsString,
    io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use codex_gui_core::worktree::{Edition, WorktreeStore};
use objc2_app_kit::NSRunningApplication;
use objc2_foundation::NSString;
use uuid::Uuid;

const BUNDLE_IDENTIFIER: &str = "local.codexgui.appkit";
const EXECUTABLE: &str = "CodexGUI";
pub const ARGUMENT: &str = "--verify-appkit-retirement";
pub const PREFLIGHT: &str = "--check-appkit-retirement";

/// The legacy installer retires its selected bundle and closes legacy processes before sealing
/// the records. Relaunching the pinned AppKit code after the seal fails at its native store lock.
pub fn ensure_appkit_retired(installed_bundle: &Path) -> io::Result<()> {
    require_quiescent(installed_bundle, BUNDLE_IDENTIFIER, EXECUTABLE)
}

pub fn preflight(mut arguments: impl Iterator<Item = OsString>) -> io::Result<()> {
    let bundle = PathBuf::from(arguments.next().ok_or(io::ErrorKind::InvalidInput)?);
    if arguments.next().is_some() {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    ensure_appkit_retired(&bundle)?;
    println!("Verified the legacy AppKit bundle and process are retired");
    Ok(())
}

fn require_quiescent(bundle: &Path, bundle_identifier: &str, executable: &str) -> io::Result<()> {
    ensure_no_bundle(bundle)?;
    if !NSRunningApplication::runningApplicationsWithBundleIdentifier(&NSString::from_str(
        bundle_identifier,
    ))
    .is_empty()
    {
        return Err(active_process());
    }
    let process = Command::new("/usr/bin/pgrep")
        .args(["-x", executable])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    match process.code() {
        Some(1) => Ok(()),
        Some(0) => Err(active_process()),
        _ => Err(io::Error::other(
            "could not check the legacy AppKit process",
        )),
    }
}

fn active_process() -> io::Error {
    io::Error::new(
        io::ErrorKind::ResourceBusy,
        "quit the legacy AppKit process",
    )
}

fn ensure_no_bundle(installed_bundle: &Path) -> io::Result<()> {
    if !installed_bundle.is_absolute() || installed_bundle.extension() != Some("app".as_ref()) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "expected the former AppKit bundle path",
        ));
    }
    match installed_bundle.symlink_metadata() {
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "retire the AppKit bundle before transfer",
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

pub fn verify(arguments: impl Iterator<Item = OsString>) -> Result<(), Box<dyn std::error::Error>> {
    let paths = arguments.map(PathBuf::from).collect::<Vec<_>>();
    let [profile, bundle] = paths.as_slice() else {
        return Err(
            "expected the isolated retirement fixture profile and former bundle path".into(),
        );
    };
    if !profile.is_absolute()
        || profile.join(".appkit-retirement-fixture").read_link()? != Path::new("fixture")
        || bundle.parent() != Some(profile.as_path())
        || !profile.join("records").symlink_metadata()?.is_dir()
    {
        return Err("the isolated retirement fixture is unavailable".into());
    }
    let store = WorktreeStore::open(&profile.join("records"))?;
    // Keep the process check on the same native API path while the fixture identifier
    // isolates this probe from the user's own edition.
    let transfer = Uuid::from_u128(1);
    let lock = store.lock_for(Edition::AppKit)?;
    require_quiescent(bundle, "local.codexgui.appkit.fixture", "AppKitLockQA")?;
    lock.retire_appkit(transfer)?;
    if !store.retired_appkit(transfer)? || store.retired_appkit(Uuid::from_u128(2))? {
        return Err("the native records did not retain the captured AppKit retirement".into());
    }
    println!("Verified durable AppKit management retirement");
    Ok(())
}
