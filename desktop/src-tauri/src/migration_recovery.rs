use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs::{self, File},
    io::{self, Read, Write},
    path::{Component, Path, PathBuf},
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    storage::attachments::{AttachmentStore, appkit_preferences::AppKitPreferences},
    worktree::{Edition, WorktreeManager, WorktreeStore},
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const ARGUMENT: &str = "--tauri-recovery";
const MANIFEST: &str = "recovery-manifest.json";
const APPKIT_MANIFEST: &str = "appkit-copy-manifest.json";
const DATABASE: &str = "workspace.sqlite3";
const FILES: &[&str] = &[
    DATABASE,
    "presentation.json",
    "notifications.json",
    "remote-host-v1.json",
    "appkit-worktree-transfer.json",
];
const DIRECTORIES: &[&str] = &[
    "worktrees",
    "notification-sounds",
    "workspace.sqlite3.attachments/blobs",
];
type Failure = Box<dyn std::error::Error>;

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Manifest {
    version: u32,
    files: BTreeMap<PathBuf, String>,
}

pub async fn run(mut arguments: impl Iterator<Item = OsString>) -> Result<(), Failure> {
    let mode = arguments
        .next()
        .ok_or("expected verify-appkit, backup, or restore")?;
    let paths = arguments.map(PathBuf::from).collect::<Vec<_>>();
    let [first, second] = paths.as_slice() else {
        return Err("expected two absolute paths".into());
    };
    if !first.is_absolute() || !second.is_absolute() {
        return Err("expected two absolute paths".into());
    }
    match mode.to_str() {
        Some("verify-appkit") => {
            verify_appkit_copy(first, second)?;
            println!("Verified the staged AppKit source copy");
        }
        Some("backup") => {
            backup(first, second)?;
            println!("Saved a verified Tauri recovery copy");
        }
        Some("restore") => {
            restore(first, second).await?;
            println!("Reopened the Tauri profile with its worktree ownership");
        }
        Some("fixture-new-work") => {
            crate::fixture::create_recovery_work(first, second).await?;
            println!("Created a new Tauri-managed fixture task and draft");
        }
        _ => return Err("expected verify-appkit, backup, or restore".into()),
    }
    Ok(())
}

fn verify_appkit_copy(root: &Path, original_images: &Path) -> Result<(), Failure> {
    let source = AppKitPreferences::open(root, original_images)?;
    if stage_manifest_if_present(source.root())? {
        return Ok(());
    }
    let scratch = tempfile::tempdir()?;
    let store = AttachmentStore::open(&scratch.path().join(DATABASE))?;
    source.import(&store)?;
    source.presentation()?;
    source.notification_preferences()?;
    let files = inventory(source.root(), None, APPKIT_MANIFEST)?;
    if files.keys().any(|relative| {
        !["preferences.plist", "remote-preferences.plist"]
            .iter()
            .any(|file| relative == Path::new(file))
            && !["project-context", "draft-images", "notification-sounds"]
                .iter()
                .any(|directory| relative.starts_with(directory))
    }) {
        return Err("the staged AppKit copy contains data outside the supported preferences and owned assets".into());
    }
    write_manifest(source.root(), APPKIT_MANIFEST, files)?;
    stage_manifest_if_present(source.root())?;
    Ok(())
}

pub fn stage_manifest_if_present(root: &Path) -> Result<bool, Failure> {
    let target = root.join(APPKIT_MANIFEST);
    match target.symlink_metadata() {
        Ok(_) => {
            verify_manifest(root, APPKIT_MANIFEST)?;
            Ok(true)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn backup(profile: &Path, destination: &Path) -> Result<(), Failure> {
    let profile = native_directory(profile)?;
    let (destination, parent) = target_path(destination)?;
    if destination.starts_with(&profile)
        || profile.starts_with(&destination)
        || destination.try_exists()?
    {
        return Err("use a new recovery directory outside the Tauri profile".into());
    }
    let database = profile.join(DATABASE);
    if !database.symlink_metadata()?.is_file() {
        return Err("the Tauri workspace database is unavailable".into());
    }
    let store = AttachmentStore::open(&database)?;
    let records = WorktreeStore::initialize_tauri(&profile.join("worktrees"))?;
    let _locked = records.lock_for(Edition::Tauri)?;
    let temporary = tempfile::tempdir_in(&parent)?;
    let root = temporary.path();
    store.snapshot_database(&root.join(DATABASE))?;
    File::open(root.join(DATABASE))?.sync_all()?;
    for relative in FILES.iter().skip(1).chain(DIRECTORIES) {
        let source = profile.join(relative);
        match source.symlink_metadata() {
            Ok(_) => copy_tree(&source, &root.join(relative))?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    let files = inventory(root, None, MANIFEST)?;
    write_manifest(root, MANIFEST, files)?;
    verify_manifest(root, MANIFEST)?;
    publish(temporary, &destination, &parent)?;
    Ok(())
}

async fn restore(copy: &Path, destination: &Path) -> Result<(), Failure> {
    let copy = native_directory(copy)?;
    let (destination, parent) = target_path(destination)?;
    if destination.starts_with(&copy) || copy.starts_with(&destination) {
        return Err("use separate recovery and profile directories".into());
    }
    let entries = verify_manifest(&copy, MANIFEST)?;
    if destination.symlink_metadata().is_ok() {
        native_directory(&destination)?;
        if fs::read_dir(&destination)?.next().is_some() {
            let existing = destination.join(DATABASE);
            if existing.symlink_metadata()?.is_file() {
                crate::appkit_transfer::resume(&destination).await?;
                let _store = AttachmentStore::open(&existing)?;
                verify_worktrees(&destination).await?;
                return Ok(());
            }
            return Err("the destination contains data from another profile".into());
        }
    }
    if !entries.files.contains_key(Path::new(DATABASE)) {
        return Err("the recovery copy is missing its workspace database".into());
    }
    let temporary = tempfile::tempdir_in(&parent)?;
    for relative in entries.files.keys() {
        if !restore_path(relative) {
            return Err("the recovery copy contains data outside the Tauri profile".into());
        }
        copy_tree(&copy.join(relative), &temporary.path().join(relative))?;
    }
    let actual = inventory(temporary.path(), None, MANIFEST)?;
    if actual != entries.files {
        return Err("the recovery copy changed during restoration".into());
    }
    crate::appkit_transfer::resume(temporary.path()).await?;
    let store = AttachmentStore::open(&temporary.path().join(DATABASE))?;
    verify_worktrees(temporary.path()).await?;
    drop(store);
    publish(temporary, &destination, &parent)?;
    Ok(())
}

async fn verify_worktrees(profile: &Path) -> Result<(), Failure> {
    let path = profile.join("worktrees");
    let store = WorktreeStore::initialize_tauri(&path)?;
    let locked = store.lock_for(Edition::Tauri)?;
    for record in locked.list()? {
        let root = record
            .checkout_path
            .parent()
            .ok_or("missing recorded checkout parent")?;
        let manager = WorktreeManager::new(
            WorktreeStore::open(&path)?,
            CheckoutIdentity::capture(root)?,
        );
        manager.capture_appkit_record(record).await?;
    }
    Ok(())
}

fn restore_path(relative: &Path) -> bool {
    relative
        .components()
        .all(|part| matches!(part, Component::Normal(_)))
        && (FILES.iter().any(|file| relative == Path::new(file))
            || DIRECTORIES
                .iter()
                .any(|dir| relative.starts_with(dir) && relative != Path::new(dir)))
        && relative.file_name() != Some(".lock".as_ref())
}

fn copy_tree(source: &Path, target: &Path) -> io::Result<()> {
    let metadata = source.symlink_metadata()?;
    if metadata.is_dir() {
        fs::create_dir_all(target)?;
        for entry in fs::read_dir(source)? {
            let entry = entry?;
            if entry.file_name() != ".lock" {
                copy_tree(&entry.path(), &target.join(entry.file_name()))?;
            }
        }
        File::open(target)?.sync_all()
    } else if metadata.is_file() {
        fs::create_dir_all(target.parent().ok_or(io::ErrorKind::NotFound)?)?;
        let mut input = File::open(source)?;
        let mut output = File::options().create_new(true).write(true).open(target)?;
        io::copy(&mut input, &mut output)?;
        output.sync_all()
    } else {
        Err(io::Error::other(
            "a recovery input is not a regular file or directory",
        ))
    }
}

fn inventory(
    root: &Path,
    relative: Option<&Path>,
    manifest: &str,
) -> Result<BTreeMap<PathBuf, String>, Failure> {
    let directory = relative.map_or_else(|| root.to_path_buf(), |relative| root.join(relative));
    let mut files = BTreeMap::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let name = entry.file_name();
        if relative.is_none() && name == manifest {
            continue;
        }
        let path = relative.unwrap_or_else(|| Path::new("")).join(name);
        let metadata = entry.path().symlink_metadata()?;
        if metadata.is_dir() {
            files.extend(inventory(root, Some(&path), manifest)?);
        } else if metadata.is_file() {
            let mut source = File::open(entry.path())?;
            let mut hash = Sha256::new();
            let mut buffer = [0; 64 * 1024];
            loop {
                let count = source.read(&mut buffer)?;
                if count == 0 {
                    break;
                }
                hash.update(&buffer[..count]);
            }
            files.insert(path, format!("{:x}", hash.finalize()));
        } else {
            return Err("a recovery copy contains a link or special file".into());
        }
    }
    Ok(files)
}

fn write_manifest(
    root: &Path,
    name: &str,
    files: BTreeMap<PathBuf, String>,
) -> Result<(), Failure> {
    let target = root.join(name);
    let mut staged = tempfile::NamedTempFile::new_in(root)?;
    serde_json::to_writer_pretty(&mut staged, &Manifest { version: 1, files })?;
    staged.write_all(b"\n")?;
    staged.as_file().sync_all()?;
    staged
        .persist_noclobber(target)
        .map_err(|error| error.error)?;
    File::open(root)?.sync_all()?;
    Ok(())
}

fn verify_manifest(root: &Path, name: &str) -> Result<Manifest, Failure> {
    let file = root.join(name);
    let metadata = file.symlink_metadata()?;
    if !metadata.is_file() || metadata.len() > 16 * 1024 * 1024 {
        return Err("invalid recovery manifest".into());
    }
    let manifest: Manifest = serde_json::from_reader(io::BufReader::new(File::open(file)?))?;
    if manifest.version != 1 || inventory(root, None, name)? != manifest.files {
        return Err("the recovery copy differs from its verified manifest".into());
    }
    Ok(manifest)
}

fn native_directory(directory: &Path) -> io::Result<PathBuf> {
    if !directory.symlink_metadata()?.is_dir() {
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }
    directory.canonicalize()
}

fn target_path(target: &Path) -> io::Result<(PathBuf, PathBuf)> {
    let parent = native_directory(target.parent().ok_or(io::ErrorKind::NotFound)?)?;
    let leaf = target.file_name().ok_or(io::ErrorKind::InvalidInput)?;
    Ok((parent.join(leaf), parent))
}

fn publish(temporary: tempfile::TempDir, destination: &Path, parent: &Path) -> io::Result<()> {
    File::open(temporary.path())?.sync_all()?;
    fs::rename(temporary.path(), destination)?;
    File::open(parent)?.sync_all()
}
