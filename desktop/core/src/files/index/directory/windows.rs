use std::{
    ffi::{OsStr, OsString},
    fs::File,
    io,
    mem::offset_of,
    os::windows::{
        ffi::OsStringExt,
        io::{AsRawHandle, FromRawHandle},
    },
};

use windows_sys::Win32::{
    Foundation::{ERROR_NO_MORE_FILES, INVALID_HANDLE_VALUE},
    Storage::FileSystem::{
        FILE_ATTRIBUTE_DEVICE, FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT,
        FILE_FLAG_BACKUP_SEMANTICS, FILE_FULL_DIR_INFO, FILE_LIST_DIRECTORY, FILE_SHARE_DELETE,
        FILE_SHARE_READ, FILE_SHARE_WRITE, FileFullDirectoryInfo, FileFullDirectoryRestartInfo,
        GetFileInformationByHandleEx, ReOpenFile,
    },
};

use super::EntryKind;

pub(in crate::files::index) fn open_root(file: &File) -> io::Result<File> {
    // Reopen the existing directory to keep this scan's cursor independent.
    let handle = unsafe {
        ReOpenFile(
            file.as_raw_handle(),
            FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            FILE_FLAG_BACKUP_SEMANTICS,
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error());
    }
    // ReOpenFile returned a new owned handle.
    Ok(unsafe { File::from_raw_handle(handle) })
}

pub(in crate::files::index) fn visit(
    file: &File,
    mut receive: impl FnMut(&OsStr, EntryKind) -> io::Result<bool>,
) -> io::Result<bool> {
    const NAME_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFO, FileName);
    const ATTRIBUTES_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFO, FileAttributes);
    const LENGTH_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFO, FileNameLength);

    let mut aligned = vec![0u64; 4096];
    let byte_len = aligned.len() * size_of::<u64>();
    let mut mode = FileFullDirectoryRestartInfo;
    loop {
        // The directory handle is borrowed and the buffer is writable and aligned.
        let ok = unsafe {
            GetFileInformationByHandleEx(
                file.as_raw_handle(),
                mode,
                aligned.as_mut_ptr().cast(),
                byte_len as u32,
            )
        };
        if ok == 0 {
            let error = io::Error::last_os_error();
            return if error.raw_os_error() == Some(ERROR_NO_MORE_FILES as i32) {
                Ok(true)
            } else {
                Err(error)
            };
        }
        mode = FileFullDirectoryInfo;
        // All bytes are initialized, including any unused bytes in the final record.
        let mut remaining =
            unsafe { std::slice::from_raw_parts(aligned.as_ptr().cast::<u8>(), byte_len) };
        loop {
            let invalid = || io::Error::from(io::ErrorKind::InvalidData);
            let next = word(remaining, 0).ok_or_else(invalid)? as usize;
            let attributes = word(remaining, ATTRIBUTES_OFFSET).ok_or_else(invalid)?;
            let length = word(remaining, LENGTH_OFFSET).ok_or_else(invalid)? as usize;
            let end = NAME_OFFSET.checked_add(length).ok_or_else(invalid)?;
            if length == 0
                || !length.is_multiple_of(2)
                || (next != 0 && (next < end || next >= remaining.len()))
            {
                return Err(invalid());
            }
            let units: Vec<_> = remaining
                .get(NAME_OFFSET..end)
                .ok_or_else(invalid)?
                .chunks_exact(2)
                .map(|bytes| u16::from_le_bytes([bytes[0], bytes[1]]))
                .collect();
            let name = OsString::from_wide(&units);
            let kind = if attributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE) != 0 {
                EntryKind::Other
            } else if attributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
                EntryKind::Directory
            } else {
                EntryKind::File
            };
            if !receive(&name, kind)? {
                return Ok(false);
            }
            if next == 0 {
                break;
            }
            remaining = &remaining[next..];
        }
    }
}

fn word(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(offset..offset + 4)?.try_into().ok()?,
    ))
}
