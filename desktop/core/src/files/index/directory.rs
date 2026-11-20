#[cfg(unix)]
use std::{ffi::OsStr, fs::File, io};

#[derive(Clone, Copy)]
pub(super) enum EntryKind {
    Directory,
    File,
    Other,
}

#[cfg(unix)]
pub(super) fn open_root(file: &File) -> io::Result<File> {
    file.try_clone()
}

#[cfg(unix)]
pub(super) fn visit(
    file: &File,
    mut receive: impl FnMut(&OsStr, EntryKind) -> io::Result<bool>,
) -> io::Result<bool> {
    use rustix::fs::{AtFlags, Dir, FileType, statat};
    use std::os::unix::ffi::OsStrExt;

    for entry in Dir::read_from(file)? {
        let entry = entry?;
        let name = entry.file_name();
        let kind = match entry.file_type() {
            FileType::Unknown => statat(file, name, AtFlags::SYMLINK_NOFOLLOW)
                .map_or(FileType::Unknown, |stat| {
                    FileType::from_raw_mode(stat.st_mode)
                }),
            kind => kind,
        };
        let kind = match kind {
            FileType::Directory => EntryKind::Directory,
            FileType::RegularFile => EntryKind::File,
            _ => EntryKind::Other,
        };
        if !receive(OsStr::from_bytes(name.to_bytes()), kind)? {
            return Ok(false);
        }
    }
    Ok(true)
}

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub(super) use windows::{open_root, visit};
