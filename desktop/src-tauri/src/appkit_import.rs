use std::{
    ffi::OsString,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
};

use codex_gui_core::storage::attachments::{
    AttachmentStore, appkit_preferences::AppKitPreferences,
};
use serde::Serialize;

use crate::{
    desktop_presentation::DesktopPresentation, relay_ipc::RelayHost,
    task_notifications::TaskNotifications,
};

pub const ARGUMENT: &str = "--import-appkit";

pub fn run(arguments: impl Iterator<Item = OsString>) -> Result<(), Box<dyn std::error::Error>> {
    let paths = arguments.map(PathBuf::from).collect::<Vec<_>>();
    let [staged, original_images, destination] = paths.as_slice() else {
        return Err(invalid_paths().into());
    };
    if paths.iter().any(|path| !path.is_absolute()) {
        return Err(invalid_paths().into());
    }
    let source = AppKitPreferences::open(staged, original_images)?;
    let destination = fs::canonicalize(destination)?;
    if !destination.is_dir()
        || source.root().starts_with(&destination)
        || destination.starts_with(source.root())
    {
        return Err(invalid_paths().into());
    }

    let report = {
        let store = AttachmentStore::open(&destination.join("workspace.sqlite3"))?;
        let report = source.import(&store)?;
        DesktopPresentation::import_appkit(&destination, &source)?;
        TaskNotifications::import_appkit(&destination, &source)?;
        RelayHost::import_appkit(&destination, &source)?;
        report
    };
    serde_json::to_writer(io::stdout().lock(), &report)?;
    println!();
    Ok(())
}

fn invalid_paths() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "expected absolute paths for a staged AppKit copy, original image directory, and separate existing Tauri profile",
    )
}

pub(super) fn persist_new<T: Serialize>(target: &Path, data: &T) -> io::Result<()> {
    let parent = target.parent().ok_or(io::ErrorKind::NotFound)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer_pretty(&mut temporary, data)?;
    temporary.write_all(b"\n")?;
    temporary.as_file().sync_all()?;
    match temporary.persist_noclobber(target) {
        Ok(_) => Ok(()),
        Err(error) if error.error.kind() == io::ErrorKind::AlreadyExists => Ok(()),
        Err(error) => Err(error.error),
    }
}
