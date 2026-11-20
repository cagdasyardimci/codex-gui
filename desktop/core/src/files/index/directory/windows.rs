use std::{
    ffi::{OsStr, OsString},
    fs::File,
    io,
    mem::offset_of,
    os::windows::{ffi::OsStringExt, io::AsRawHandle},
    ptr::{null, null_mut},
};

use windows_sys::{
    Wdk::Storage::FileSystem::{
        FILE_FULL_DIR_INFORMATION, FileFullDirectoryInformation, NtQueryDirectoryFile,
    },
    Win32::{
        Foundation::{
            RtlNtStatusToDosError, STATUS_NO_MORE_FILES, STATUS_NO_SUCH_FILE, STATUS_SUCCESS,
        },
        Storage::FileSystem::{
            FILE_ATTRIBUTE_DEVICE, FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT,
        },
        System::IO::IO_STATUS_BLOCK,
    },
};

use super::EntryKind;
use crate::{checkout::CheckoutIdentity, files::FileError};

pub(in crate::files::index) fn open_root(checkout: &CheckoutIdentity) -> Result<File, FileError> {
    // Open an independent directory cursor and verify the original native identity.
    Ok(checkout.reopen_directory()?)
}

pub(in crate::files::index) fn visit(
    file: &File,
    mut receive: impl FnMut(&OsStr, EntryKind) -> io::Result<bool>,
) -> io::Result<bool> {
    const NAME_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFORMATION, FileName);
    const ATTRIBUTES_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFORMATION, FileAttributes);
    const LENGTH_OFFSET: usize = offset_of!(FILE_FULL_DIR_INFORMATION, FileNameLength);

    let mut aligned = vec![0u64; 4096];
    let byte_len = aligned.len() * size_of::<u64>();
    let mut restart = true;
    loop {
        let mut status = IO_STATUS_BLOCK::default();
        // The directory handle is borrowed and the buffer is writable and aligned.
        let result = unsafe {
            NtQueryDirectoryFile(
                file.as_raw_handle(),
                null_mut(),
                None,
                null(),
                &mut status,
                aligned.as_mut_ptr().cast(),
                byte_len as u32,
                FileFullDirectoryInformation,
                false,
                null(),
                restart,
            )
        };
        match result {
            STATUS_NO_MORE_FILES | STATUS_NO_SUCH_FILE => return Ok(true),
            STATUS_SUCCESS => {}
            code => {
                let source =
                    io::Error::from_raw_os_error(unsafe { RtlNtStatusToDosError(code) } as i32);
                return Err(io::Error::new(
                    source.kind(),
                    format!("enumerate captured directory: {source}"),
                ));
            }
        }
        restart = false;
        if status.Information > byte_len || status.Information == 0 {
            return Err(io::ErrorKind::InvalidData.into());
        }
        // The kernel returned the count of initialized directory data bytes.
        let mut remaining = unsafe {
            std::slice::from_raw_parts(aligned.as_ptr().cast::<u8>(), status.Information)
        };
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
