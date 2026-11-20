use std::{
    ffi::OsStr,
    fs::File,
    io,
    mem::offset_of,
    os::windows::{
        ffi::OsStrExt,
        fs::MetadataExt,
        io::{AsRawHandle, FromRawHandle},
    },
    ptr::{null, null_mut},
};

use windows_sys::{
    Wdk::{
        Foundation::OBJECT_ATTRIBUTES,
        Storage::FileSystem::{
            FILE_CREATE, FILE_DIRECTORY_FILE, FILE_NON_DIRECTORY_FILE, FILE_OPEN,
            FILE_OPEN_REPARSE_POINT, FILE_RENAME_INFORMATION, FILE_RENAME_POSIX_SEMANTICS,
            FILE_RENAME_REPLACE_IF_EXISTS, FILE_SYNCHRONOUS_IO_NONALERT, FileRenameInformationEx,
            NtCreateFile, NtSetInformationFile,
        },
    },
    Win32::{
        Foundation::{NTSTATUS, OBJ_CASE_INSENSITIVE, RtlNtStatusToDosError, UNICODE_STRING},
        Storage::FileSystem::{
            DELETE, FILE_ATTRIBUTE_NORMAL, FILE_ATTRIBUTE_REPARSE_POINT, FILE_DISPOSITION_INFO,
            FILE_GENERIC_READ, FILE_GENERIC_WRITE, FILE_READ_ATTRIBUTES, FILE_SHARE_DELETE,
            FILE_SHARE_READ, FILE_SHARE_WRITE, FILE_TRAVERSE, FileDispositionInfo, SYNCHRONIZE,
            SetFileInformationByHandle,
        },
        System::IO::IO_STATUS_BLOCK,
    },
};

const SHARE_ALL: u32 = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
const SHARE_READ_DELETE: u32 = FILE_SHARE_READ | FILE_SHARE_DELETE;

pub(in crate::files) fn open_directory(parent: &File, name: &OsStr) -> io::Result<File> {
    open(
        parent,
        name,
        FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        SHARE_ALL,
        FILE_OPEN,
        FILE_DIRECTORY_FILE,
    )
}

pub(in crate::files) fn open_read(parent: &File, name: &OsStr) -> io::Result<File> {
    open(
        parent,
        name,
        FILE_GENERIC_READ,
        SHARE_ALL,
        FILE_OPEN,
        FILE_NON_DIRECTORY_FILE,
    )
}

pub(in crate::files) fn open_for_save(parent: &File, name: &OsStr) -> io::Result<File> {
    // Demand DELETE sharing and exclude write handles until publication has completed.
    open(
        parent,
        name,
        FILE_GENERIC_READ | DELETE,
        SHARE_READ_DELETE,
        FILE_OPEN,
        FILE_NON_DIRECTORY_FILE,
    )
}

pub(super) fn create_stage(parent: &File, name: &OsStr) -> io::Result<File> {
    open(
        parent,
        name,
        FILE_GENERIC_WRITE | FILE_READ_ATTRIBUTES | DELETE,
        SHARE_READ_DELETE,
        FILE_CREATE,
        FILE_NON_DIRECTORY_FILE,
    )
}

fn open(
    parent: &File,
    name: &OsStr,
    access: u32,
    share: u32,
    disposition: u32,
    kind: u32,
) -> io::Result<File> {
    let mut units = wide_name(name)?;
    let length = (units.len() * size_of::<u16>()) as u16;
    let name = UNICODE_STRING {
        Length: length,
        MaximumLength: length,
        Buffer: units.as_mut_ptr(),
    };
    let attributes = OBJECT_ATTRIBUTES {
        Length: size_of::<OBJECT_ATTRIBUTES>() as u32,
        RootDirectory: parent.as_raw_handle(),
        ObjectName: &name,
        Attributes: OBJ_CASE_INSENSITIVE,
        SecurityDescriptor: null(),
        SecurityQualityOfService: null(),
    };
    let mut handle = null_mut();
    let mut io_status = IO_STATUS_BLOCK::default();
    // NtCreateFile receives one counted name relative to the borrowed directory handle.
    let status = unsafe {
        NtCreateFile(
            &mut handle,
            access,
            &attributes,
            &mut io_status,
            null(),
            FILE_ATTRIBUTE_NORMAL,
            share,
            disposition,
            FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_REPARSE_POINT | kind,
            null(),
            0,
        )
    };
    check_status(status)?;
    if handle.is_null() {
        return Err(io::Error::other("native file open returned no handle"));
    }
    // On success the new handle is owned by this File, including on reparse rejection.
    let file = unsafe { File::from_raw_handle(handle) };
    if file.metadata()?.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    Ok(file)
}

pub(super) fn publish_stage(
    _parent: &File,
    _stage: &OsStr,
    file: &File,
    name: &OsStr,
) -> io::Result<()> {
    let units = wide_name(name)?;
    let name_len = units.len() * size_of::<u16>();
    let name_offset = offset_of!(FILE_RENAME_INFORMATION, FileName);
    let size = (name_offset + name_len).max(size_of::<FILE_RENAME_INFORMATION>());
    let mut buffer = vec![0usize; size.div_ceil(size_of::<usize>())];
    let info = buffer.as_mut_ptr().cast::<FILE_RENAME_INFORMATION>();
    let mut io_status = IO_STATUS_BLOCK::default();
    // The initialized, aligned buffer contains the header and the complete counted name.
    // A null RootDirectory and a single component rename in the open file's own directory.
    let status = unsafe {
        (*info).Anonymous.Flags = FILE_RENAME_REPLACE_IF_EXISTS | FILE_RENAME_POSIX_SEMANTICS;
        (*info).FileNameLength = name_len as u32;
        std::ptr::copy_nonoverlapping(
            units.as_ptr(),
            info.cast::<u8>().add(name_offset).cast(),
            units.len(),
        );
        NtSetInformationFile(
            file.as_raw_handle(),
            &mut io_status,
            info.cast(),
            size as u32,
            FileRenameInformationEx,
        )
    };
    check_status(status)
}

pub(super) fn remove_stage(_parent: &File, _stage: &OsStr, file: &File) {
    let disposition = FILE_DISPOSITION_INFO { DeleteFile: true };
    // Dispose of this exact open staging file, even if its name has changed.
    unsafe {
        SetFileInformationByHandle(
            file.as_raw_handle(),
            FileDispositionInfo,
            (&disposition as *const FILE_DISPOSITION_INFO).cast(),
            size_of::<FILE_DISPOSITION_INFO>() as u32,
        )
    };
}

fn wide_name(name: &OsStr) -> io::Result<Vec<u16>> {
    let units: Vec<_> = name.encode_wide().collect();
    if units.len() > usize::from(u16::MAX) / size_of::<u16>()
        || units
            .iter()
            .any(|&unit| unit == 0 || unit == u16::from(b':'))
    {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    Ok(units)
}

fn check_status(status: NTSTATUS) -> io::Result<()> {
    if status < 0 {
        // Convert the returned NTSTATUS without consulting thread-local last error.
        return Err(io::Error::from_raw_os_error(
            unsafe { RtlNtStatusToDosError(status) } as i32,
        ));
    }
    Ok(())
}
