use std::{
    ffi::{OsStr, OsString},
    fs::File,
    io,
};

use uuid::Uuid;

use super::NativeFileIdentity;

#[cfg(unix)]
mod unix;
#[cfg(windows)]
mod windows;
#[cfg(unix)]
use unix as os;
#[cfg(windows)]
use windows as os;

pub(super) use os::{open_for_save, open_read};
#[cfg(unix)]
pub(super) use unix::open_directory as open_index_directory;
#[cfg(windows)]
pub(super) use windows::open_index_directory;

pub(super) fn open_parent(root: &File, components: &[&OsStr]) -> io::Result<Option<File>> {
    let mut parent = None;
    for component in components {
        parent = Some(os::open_directory(
            parent.as_ref().unwrap_or(root),
            component,
        )?);
    }
    Ok(parent)
}

pub(super) struct StagedFile<'a> {
    parent: &'a File,
    name: OsString,
    file: File,
    published: bool,
}

impl<'a> StagedFile<'a> {
    pub(super) fn new(parent: &'a File) -> io::Result<Self> {
        let name = OsString::from(format!(".codex-files-{}", Uuid::new_v4()));
        let file = os::create_stage(parent, &name)?;
        Ok(Self {
            parent,
            name,
            file,
            published: false,
        })
    }

    pub(super) fn file(&self) -> &File {
        &self.file
    }

    pub(super) fn read_anchor(&self) -> io::Result<File> {
        let anchor = open_read(self.parent, &self.name)?;
        if NativeFileIdentity::from_file(&self.file, &self.file.metadata()?)?
            != NativeFileIdentity::from_file(&anchor, &anchor.metadata()?)?
        {
            return Err(io::Error::other("staged file was replaced"));
        }
        Ok(anchor)
    }

    pub(super) fn publish(mut self, name: &OsStr) -> io::Result<()> {
        os::publish_stage(self.parent, &self.name, &self.file, name)?;
        self.published = true;
        Ok(())
    }
}

impl Drop for StagedFile<'_> {
    fn drop(&mut self) {
        if !self.published {
            os::remove_stage(self.parent, &self.name, &self.file);
        }
    }
}
