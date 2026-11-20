use std::{
    ffi::OsString,
    fs::{self, File},
    io::{self, Write},
    path::{Path, PathBuf},
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    storage::attachments::AttachmentStore,
    worktree::{Edition, WorktreeManager, WorktreeRecord, WorktreeStore},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::appkit_retirement::{ensure_appkit_retired, ensure_fixture_retired};

pub const ARGUMENT: &str = "--transfer-appkit-worktrees";
const JOURNAL: &str = "appkit-worktree-transfer.json";
const MAX_JOURNAL_BYTES: u64 = 16 * 1024 * 1024;
type Failure = Box<dyn std::error::Error>;

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Transfer {
    version: u32,
    id: Uuid,
    source_records: PathBuf,
    source_identity: String,
    former_bundle: PathBuf,
    source: Vec<WorktreeRecord>,
    adopted: Vec<WorktreeRecord>,
    completed: bool,
}

pub async fn run(arguments: impl Iterator<Item = OsString>) -> Result<(), Failure> {
    let mut arguments = arguments;
    let mode = arguments
        .next()
        .ok_or("expected prepare, commit, or abandon")?;
    let profile = PathBuf::from(arguments.next().ok_or("expected the Tauri profile")?);
    let profile = absolute_directory(&profile)?;
    if mode == "resume" && arguments.next().is_none() {
        resume(&profile).await?;
        println!("Reopened the AppKit worktree handoff");
        return Ok(());
    }
    let data = AttachmentStore::open(&profile.join("workspace.sqlite3"))?;
    let target = profile.join(JOURNAL);
    match mode.to_str() {
        Some("prepare") => {
            let source = PathBuf::from(
                arguments
                    .next()
                    .ok_or("expected the AppKit records directory")?,
            );
            let bundle = PathBuf::from(
                arguments
                    .next()
                    .ok_or("expected the former AppKit bundle path")?,
            );
            if arguments.next().is_some() {
                return Err("unexpected transfer path".into());
            }
            prepare(&profile, &target, &source, &bundle).await?;
            println!("Prepared the AppKit worktree handoff");
        }
        Some("commit" | "abandon") if arguments.next().is_none() => {
            let mut transfer = read_transfer(&target)?.ok_or("no prepared AppKit handoff")?;
            let source = source_store(&transfer)?;
            if mode == "abandon" {
                if source.retired_appkit(transfer.id)? {
                    return Err("the AppKit handoff is already committed".into());
                }
                let _locked = source.lock_for(Edition::AppKit)?;
                fs::remove_file(&target)?;
                sync(&profile)?;
                println!("Abandoned the prepared handoff");
            } else {
                complete(&profile, &target, &data, &mut transfer).await?;
                println!("Committed the one-way AppKit worktree handoff");
            }
        }
        _ => return Err("expected prepare, commit, or abandon".into()),
    }
    Ok(())
}

/// A restart after sealing AppKit completes the recorded transfer before opening the writable UI.
pub async fn resume(profile: &Path) -> Result<(), Failure> {
    let target = profile.join(JOURNAL);
    let Some(mut transfer) = read_transfer(&target)? else {
        return Ok(());
    };
    let source = source_store(&transfer)?;
    if transfer.completed || source.retired_appkit(transfer.id)? {
        if !source.retired_appkit(transfer.id)? {
            return Err("the original AppKit retirement could not be verified".into());
        }
        if !transfer.completed {
            let data = AttachmentStore::open(&profile.join("workspace.sqlite3"))?;
            complete(profile, &target, &data, &mut transfer).await?;
        }
    }
    Ok(())
}

async fn prepare(
    profile: &Path,
    target: &Path,
    records: &Path,
    bundle: &Path,
) -> Result<(), Failure> {
    if target.symlink_metadata().is_ok() {
        return Err("an AppKit handoff already exists for this profile".into());
    }
    let records = absolute_directory(records)?;
    if records.starts_with(profile)
        || profile.starts_with(&records)
        || records.file_name() != Some("records".as_ref())
        || !bundle.is_absolute()
        || bundle.extension() != Some("app".as_ref())
    {
        return Err(
            "expected separate AppKit records, former bundle and Tauri profile paths".into(),
        );
    }
    let source_path = CheckoutIdentity::capture(&records)?;
    let source = WorktreeStore::open(&records)?;
    let locked = source.lock_for(Edition::AppKit)?;
    let original = locked.list()?;
    let adopted = capture_records(&records, &original).await?;
    let destination = WorktreeStore::initialize_tauri(&profile.join("worktrees"))?;
    destination
        .lock_for(Edition::Tauri)?
        .check_adoption(&adopted)?;
    let transfer = Transfer {
        version: 1,
        id: Uuid::new_v4(),
        source_records: records,
        source_identity: source_path.storage_key(),
        former_bundle: bundle.into(),
        source: original,
        adopted,
        completed: false,
    };
    persist(target, &transfer, true)?;
    Ok(())
}

async fn complete(
    profile: &Path,
    target: &Path,
    data: &AttachmentStore,
    transfer: &mut Transfer,
) -> Result<(), Failure> {
    let source = source_store(transfer)?;
    let destination = WorktreeStore::initialize_tauri(&profile.join("worktrees"))?;
    let destination = destination.lock_for(Edition::Tauri)?;
    if transfer.completed {
        if !source.retired_appkit(transfer.id)? {
            return Err("the original AppKit retirement could not be verified".into());
        }
        return Ok(());
    }
    destination.check_adoption(&transfer.adopted)?;
    if !source.retired_appkit(transfer.id)? {
        let locked = source.lock_for(Edition::AppKit)?;
        if locked.list()? != transfer.source
            || capture_records(source.path(), &transfer.source).await? != transfer.adopted
        {
            return Err("AppKit checkout records changed after preparation".into());
        }
        let fixture = std::env::temp_dir()
            .canonicalize()
            .is_ok_and(|temporary| profile.starts_with(temporary))
            && fs::read(profile.join(".appkit-cutover-fixture"))
                .is_ok_and(|data| data == b"isolated cutover\n")
            && transfer
                .source_records
                .starts_with(profile.parent().ok_or("missing verification root")?)
            && transfer
                .former_bundle
                .starts_with(profile.parent().ok_or("missing verification root")?);
        if fixture {
            ensure_fixture_retired(&transfer.former_bundle)?;
        } else {
            ensure_appkit_retired(&transfer.former_bundle)?;
        }
        locked.retire_appkit(transfer.id)?;
        if fixture
            && std::env::var_os("CODEX_GUI_QA_STOP_AFTER_APPKIT_SEAL").as_deref()
                == Some("1".as_ref())
        {
            return Err("fixture interrupted after AppKit retirement".into());
        }
    }
    if !source.retired_appkit(transfer.id)? {
        return Err("the original AppKit management lock remains active".into());
    }
    if capture_records(source.path(), &transfer.source).await? != transfer.adopted {
        return Err("a recorded checkout changed after AppKit retirement".into());
    }
    // The durable AppKit marker is the commit boundary. A restart can repeat each
    // destination insertion and execute the same evidence adoption transaction.
    for record in &transfer.adopted {
        match destination.load(record.id)? {
            Some(existing) if &existing == record => {}
            Some(_) => {
                return Err("a newer Tauri worktree record owns the transferred identity".into());
            }
            None => destination.save(None, record)?,
        }
    }
    data.admit_appkit_execution()?;
    transfer.completed = true;
    persist(target, transfer, false)?;
    Ok(())
}

async fn capture_records(
    path: &Path,
    records: &[WorktreeRecord],
) -> Result<Vec<WorktreeRecord>, Failure> {
    if records.is_empty() {
        return Ok(Vec::new());
    }
    let checkouts = path
        .parent()
        .ok_or("missing AppKit workspace root")?
        .join("checkouts");
    let manager = WorktreeManager::new(
        WorktreeStore::open(path)?,
        CheckoutIdentity::capture(&checkouts)?,
    );
    let mut captured = Vec::with_capacity(records.len());
    for record in records {
        captured.push(manager.capture_appkit_record(record.clone()).await?);
    }
    Ok(captured)
}

fn source_store(transfer: &Transfer) -> Result<WorktreeStore, Failure> {
    let source = CheckoutIdentity::capture(&transfer.source_records)?;
    if source.storage_key() != transfer.source_identity {
        return Err("the original AppKit records directory has been replaced".into());
    }
    Ok(WorktreeStore::open(source.canonical_path())?)
}

fn absolute_directory(path: &Path) -> Result<PathBuf, Failure> {
    if !path.is_absolute() || !path.symlink_metadata()?.is_dir() {
        return Err("expected an absolute, existing directory path".into());
    }
    Ok(path.canonicalize()?)
}

fn read_transfer(path: &Path) -> Result<Option<Transfer>, Failure> {
    let metadata = match path.symlink_metadata() {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    if !metadata.is_file() || metadata.len() > MAX_JOURNAL_BYTES {
        return Err("invalid AppKit worktree transfer record".into());
    }
    let transfer: Transfer = serde_json::from_reader(io::BufReader::new(File::open(path)?))?;
    if transfer.version != 1
        || transfer.id.is_nil()
        || transfer.source.len() != transfer.adopted.len()
    {
        return Err("unsupported AppKit worktree transfer record".into());
    }
    Ok(Some(transfer))
}

fn persist(target: &Path, transfer: &Transfer, new: bool) -> Result<(), Failure> {
    let parent = target.parent().ok_or("missing Tauri transfer directory")?;
    let bytes = serde_json::to_vec_pretty(transfer)?;
    if bytes.len() as u64 > MAX_JOURNAL_BYTES {
        return Err("the AppKit transfer record exceeds its storage limit".into());
    }
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    staged.write_all(&bytes)?;
    staged.write_all(b"\n")?;
    staged.as_file().sync_all()?;
    if new {
        staged
            .persist_noclobber(target)
            .map_err(|error| error.error)?;
    } else {
        staged.persist(target).map_err(|error| error.error)?;
    }
    sync(parent)?;
    Ok(())
}

fn sync(directory: &Path) -> io::Result<()> {
    File::open(directory)?.sync_all()
}
