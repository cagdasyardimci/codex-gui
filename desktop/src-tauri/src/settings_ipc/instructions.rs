use std::{io, path::Path};

use codex_gui_core::{
    files::{CheckoutFiles, FileError, FileHandle, FileRevision},
    ipc::{InstructionsView, SaveInstructions},
};

use super::*;

const INSTRUCTIONS_FILE: &str = "AGENTS.md";
const MAX_BYTES: usize = 1024 * 1024;

pub(super) struct InstructionsFile {
    files: CheckoutFiles,
    home: CheckoutIdentity,
    disk: Option<(FileHandle, FileRevision)>,
    revision: Uuid,
    text: String,
    bom: bool,
    crlf: bool,
}

enum InstructionAction {
    Read,
    Save { revision: Uuid, text: String },
}

#[tauri::command]
pub async fn read_settings_instructions(
    window: WebviewWindow,
    session: Uuid,
) -> Result<InstructionsView, IpcError> {
    instructions(window, session, InstructionAction::Read).await
}

#[tauri::command]
pub async fn save_settings_instructions(
    window: WebviewWindow,
    update: SaveInstructions,
) -> Result<InstructionsView, IpcError> {
    instructions(
        window,
        update.session,
        InstructionAction::Save {
            revision: update.revision,
            text: update.text,
        },
    )
    .await
}

async fn instructions(
    window: WebviewWindow,
    session: Uuid,
    action: InstructionAction,
) -> Result<InstructionsView, IpcError> {
    authorize_view(&window)?;
    let source = window.clone();
    let view = tauri::async_runtime::spawn_blocking(move || {
        let settings = source.state::<SettingsIpc>();
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        let current = selected
            .as_mut()
            .filter(|view| view.id == session)
            .ok_or(IpcError::StaleSelection)?;
        let home = current
            .backend
            .as_ref()
            .and_then(|backend| backend.home.clone())
            .ok_or(IpcError::StaleSelection)?;
        match action {
            InstructionAction::Read => {
                current.instructions = Some(InstructionsFile::open(home).map_err(file_error)?)
            }
            InstructionAction::Save { revision, text } => {
                let file = current
                    .instructions
                    .as_mut()
                    .filter(|file| file.revision == revision)
                    .ok_or(IpcError::StaleSelection)?;
                file.save(text).map_err(file_error)?;
            }
        }
        let file = current
            .instructions
            .as_ref()
            .expect("captured instructions file");
        Ok::<_, IpcError>(InstructionsView {
            revision: file.revision,
            text: file.text.clone(),
        })
    })
    .await
    .map_err(report)??;
    authorize_view(&window)?;
    let settings = window.state::<SettingsIpc>();
    let selected = settings.selected.lock().expect("settings lock poisoned");
    if selected
        .as_ref()
        .filter(|current| current.id == session)
        .and_then(|current| current.instructions.as_ref())
        .is_none_or(|file| file.revision != view.revision)
    {
        return Err(IpcError::StaleSelection);
    }
    Ok(view)
}

impl InstructionsFile {
    pub(super) fn matches_home(&self, home: Option<&CheckoutIdentity>) -> bool {
        home == Some(&self.home)
    }

    fn open(home: CheckoutIdentity) -> Result<Self, FileError> {
        home.revalidate()?;
        let mut files = CheckoutFiles::new(home.clone());
        let mut text = String::new();
        let mut bom = false;
        let mut crlf = false;
        let disk = match files.issue(Path::new(INSTRUCTIONS_FILE)) {
            Ok(link) => {
                let read = files.read_limited(link.id, MAX_BYTES as u64)?;
                let source =
                    std::str::from_utf8(&read.bytes).map_err(|_| FileError::UnsupportedEncoding)?;
                let body = source.strip_prefix('\u{feff}').unwrap_or(source);
                bom = body.len() != source.len();
                crlf = body.contains("\r\n");
                text = body.replace("\r\n", "\n");
                Some((link.id, read.revision))
            }
            Err(FileError::Io(error)) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(error),
        };
        Ok(Self {
            files,
            home,
            disk,
            revision: Uuid::new_v4(),
            text,
            bom,
            crlf,
        })
    }

    fn save(&mut self, text: String) -> Result<(), FileError> {
        if text.len() > MAX_BYTES {
            return Err(FileError::TooLarge);
        }
        let canonical = text.replace("\r\n", "\n");
        let encoded = if self.crlf {
            canonical.replace('\n', "\r\n")
        } else {
            canonical.clone()
        };
        let bytes = if self.bom {
            format!("\u{feff}{encoded}")
        } else {
            encoded
        };
        if bytes.len() > MAX_BYTES {
            return Err(FileError::TooLarge);
        }
        self.disk = Some(match &self.disk {
            Some((id, digest)) => (*id, self.files.save_text(*id, digest, &bytes)?),
            None => {
                let (link, digest) = self
                    .files
                    .create_text(Path::new(INSTRUCTIONS_FILE), &bytes)?;
                (link.id, digest)
            }
        });
        self.revision = Uuid::new_v4();
        self.text = canonical;
        Ok(())
    }
}

fn file_error(error: FileError) -> IpcError {
    match error {
        FileError::Changed | FileError::Replaced | FileError::InvalidHandle => {
            IpcError::StaleSelection
        }
        FileError::Io(ref error)
            if matches!(
                error.kind(),
                io::ErrorKind::NotFound | io::ErrorKind::AlreadyExists
            ) =>
        {
            IpcError::StaleSelection
        }
        error => report(error),
    }
}
