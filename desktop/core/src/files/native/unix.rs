use std::{
    ffi::{CString, OsStr},
    fs::File,
    io,
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::ffi::OsStrExt,
    },
};

use super::NativeFileIdentity;

pub(in crate::files) fn open_directory(parent: &File, name: &OsStr) -> io::Result<File> {
    open(parent, name, libc::O_RDONLY | libc::O_DIRECTORY)
}

pub(in crate::files) fn open_read(parent: &File, name: &OsStr) -> io::Result<File> {
    open(parent, name, libc::O_RDONLY | libc::O_NONBLOCK)
}

pub(in crate::files) use open_read as open_for_save;

pub(in crate::files) fn create_stage(parent: &File, name: &OsStr) -> io::Result<File> {
    open(parent, name, libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL)
}

fn open(parent: &File, name: &OsStr, flags: i32) -> io::Result<File> {
    let name = CString::new(name.as_bytes())?;
    // The parent is live and name is a single, NUL-terminated native component.
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            flags | libc::O_CLOEXEC | libc::O_NOFOLLOW,
            0o600 as libc::c_uint,
        )
    };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    // A successful openat returns a new descriptor owned by this File.
    Ok(unsafe { File::from_raw_fd(fd) })
}

pub(super) fn publish_stage(
    parent: &File,
    stage: &OsStr,
    file: &File,
    name: &OsStr,
    replace: bool,
) -> io::Result<()> {
    verify_stage(parent, stage, file)?;
    let source = CString::new(stage.as_bytes())?;
    let name = CString::new(name.as_bytes())?;
    let dir = parent.as_raw_fd();
    // Both names are single components relative to the same open directory.
    let result = unsafe {
        if replace {
            libc::renameat(dir, source.as_ptr(), dir, name.as_ptr())
        } else {
            libc::linkat(dir, source.as_ptr(), dir, name.as_ptr(), 0)
        }
    };
    if result != 0 {
        return Err(io::Error::last_os_error());
    }
    if !replace {
        remove_stage(parent, stage, file);
    }
    Ok(())
}

pub(super) fn remove_stage(parent: &File, stage: &OsStr, file: &File) {
    if verify_stage(parent, stage, file).is_ok()
        && let Ok(stage) = CString::new(stage.as_bytes())
    {
        // Cleanup is anchored to the same open directory used by creation.
        unsafe { libc::unlinkat(parent.as_raw_fd(), stage.as_ptr(), 0) };
    }
}

fn verify_stage(parent: &File, stage: &OsStr, file: &File) -> io::Result<()> {
    let live = open_read(parent, stage)?;
    if NativeFileIdentity::from_file(&live, &live.metadata()?)?
        != NativeFileIdentity::from_file(file, &file.metadata()?)?
    {
        return Err(io::Error::other("staged file was replaced"));
    }
    Ok(())
}
