use std::{fs::Permissions, io::Write, sync::Mutex};

use super::*;

pub const MAX_EDIT_BYTES: u64 = 8 * 1024 * 1024;

// Serialize final check and publication across file scopes in this process.
static REPLACEMENT: Mutex<()> = Mutex::new(());

impl CheckoutFiles {
    /// Publishes a new UTF-8 file against the anchored parent without overwriting an existing entry.
    pub fn create_text(
        &mut self,
        relative: &Path,
        text: &str,
    ) -> Result<(FileLink, FileRevision), FileError> {
        if text.len() as u64 > MAX_EDIT_BYTES {
            return Err(FileError::TooLarge);
        }
        let components = path_components(relative)?;
        let (name, directories) = components.split_last().ok_or(FileError::InvalidPath)?;
        self.checkout.revalidate()?;
        let root = self.checkout.directory();
        let parent = native::open_parent(root, directories)?;
        let parent = parent.as_ref().unwrap_or(root);
        let parent_identity = NativeFileIdentity::from_file(parent, &parent.metadata()?)?;
        let staged = native::StagedFile::new(parent)?;
        staged.file().write_all(text.as_bytes())?;
        staged.file().sync_all()?;
        let anchor = staged.read_anchor()?;
        let identity = NativeFileIdentity::from_file(&anchor, &anchor.metadata()?)?;
        let _guard = REPLACEMENT.lock().map_err(|_| FileError::Changed)?;
        self.checkout.revalidate()?;
        let published_parent = native::open_parent(root, directories)?;
        let published_parent = published_parent.as_ref().unwrap_or(root);
        if NativeFileIdentity::from_file(published_parent, &published_parent.metadata()?)?
            != parent_identity
        {
            return Err(FileError::Replaced);
        }
        staged.publish_new(name)?;
        let id = FileHandle(Uuid::new_v4());
        self.files.insert(
            id,
            CapturedFile {
                relative: relative.to_path_buf(),
                identity,
                _anchor: anchor,
            },
        );
        Ok((
            FileLink {
                id,
                display_path: relative.to_string_lossy().into_owned(),
            },
            FileRevision::from_bytes(text.as_bytes()),
        ))
    }

    /// Validates the captured file and disk revision, leaving ownership of text with the caller.
    pub fn save_text(
        &mut self,
        handle: FileHandle,
        expected: &FileRevision,
        text: &str,
    ) -> Result<FileRevision, FileError> {
        let captured = self
            .files
            .get_mut(&handle)
            .ok_or(FileError::InvalidHandle)?;
        if text.len() as u64 > MAX_EDIT_BYTES {
            return Err(FileError::TooLarge);
        }
        let components = path_components(&captured.relative)?;
        let (name, directories) = components.split_last().ok_or(FileError::InvalidPath)?;
        self.checkout.revalidate()?;
        let root = self.checkout.directory();
        let parent = native::open_parent(root, directories)?;
        let parent = parent.as_ref().unwrap_or(root);
        let parent_identity = NativeFileIdentity::from_file(parent, &parent.metadata()?)?;

        let source = native::open_read(parent, name)?;
        let permissions = verify_save_input(captured, &source, expected)?;
        drop(source);
        let revision = FileRevision::from_bytes(text.as_bytes());
        let staged = native::StagedFile::new(parent)?;
        staged.file().write_all(text.as_bytes())?;
        staged.file().set_permissions(permissions.clone())?;
        staged.file().sync_all()?;
        let anchor = staged.read_anchor()?;
        let identity = NativeFileIdentity::from_file(&anchor, &anchor.metadata()?)?;

        let _guard = REPLACEMENT.lock().map_err(|_| FileError::Changed)?;
        self.checkout.revalidate()?;
        let published_parent = native::open_parent(root, directories)?;
        let published_parent = published_parent.as_ref().unwrap_or(root);
        if NativeFileIdentity::from_file(published_parent, &published_parent.metadata()?)?
            != parent_identity
        {
            return Err(FileError::Replaced);
        }
        let current = native::open_for_save(parent, name)?;
        current.try_lock().map_err(io::Error::from)?;
        if verify_save_input(captured, &current, expected)? != permissions {
            return Err(FileError::Changed);
        }
        if revision == *expected {
            return Ok(revision);
        }
        staged.publish(name)?;
        captured._anchor = anchor;
        captured.identity = identity;
        Ok(revision)
    }
}

fn verify_save_input(
    captured: &CapturedFile,
    file: &File,
    expected: &FileRevision,
) -> Result<Permissions, FileError> {
    let metadata = captured.verify_identity(file)?;
    let permissions = metadata.permissions();
    if permissions.readonly() {
        return Err(FileError::ReadOnly);
    }
    let current = read_bounded(file, MAX_EDIT_BYTES)?;
    if &current.revision != expected {
        return Err(FileError::Changed);
    }
    std::str::from_utf8(&current.bytes).map_err(|_| FileError::UnsupportedEncoding)?;
    Ok(permissions)
}
