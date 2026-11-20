use std::{ffi::OsStr, fs::File, io};

pub(super) fn open_contained(root: &File, components: &[&OsStr]) -> io::Result<File> {
    let (name, directories) = components.split_last().ok_or(io::ErrorKind::InvalidInput)?;
    let mut parent = None;
    for component in directories {
        parent = Some(open_component(
            parent.as_ref().unwrap_or(root),
            component,
            true,
        )?);
    }
    open_component(parent.as_ref().unwrap_or(root), name, false)
}

#[cfg(unix)]
fn open_component(parent: &File, name: &OsStr, directory: bool) -> io::Result<File> {
    use std::{
        ffi::CString,
        os::{
            fd::{AsRawFd, FromRawFd},
            unix::ffi::OsStrExt,
        },
    };

    let name = CString::new(name.as_bytes())?;
    let kind = if directory {
        libc::O_DIRECTORY
    } else {
        libc::O_NONBLOCK
    };
    // The parent is live and name is a single, NUL-terminated native component.
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            libc::O_RDONLY | libc::O_CLOEXEC | libc::O_NOFOLLOW | kind,
        )
    };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    // A successful openat returns a new descriptor owned by this File.
    Ok(unsafe { File::from_raw_fd(fd) })
}

#[cfg(windows)]
fn open_component(parent: &File, name: &OsStr, directory: bool) -> io::Result<File> {
    use std::{
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
                FILE_DIRECTORY_FILE, FILE_NON_DIRECTORY_FILE, FILE_OPEN_REPARSE_POINT,
                FILE_SYNCHRONOUS_IO_NONALERT, NtOpenFile,
            },
        },
        Win32::{
            Foundation::{OBJ_CASE_INSENSITIVE, RtlNtStatusToDosError, UNICODE_STRING},
            Storage::FileSystem::{
                FILE_ATTRIBUTE_REPARSE_POINT, FILE_GENERIC_READ, FILE_READ_ATTRIBUTES,
                FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE, FILE_TRAVERSE, SYNCHRONIZE,
            },
            System::IO::IO_STATUS_BLOCK,
        },
    };

    let mut units: Vec<_> = name.encode_wide().collect();
    if units
        .iter()
        .any(|&unit| unit == 0 || unit == u16::from(b':'))
    {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    let length =
        u16::try_from(units.len() * size_of::<u16>()).map_err(|_| io::ErrorKind::InvalidInput)?;
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
    let (access, kind) = if directory {
        (
            FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
            FILE_DIRECTORY_FILE,
        )
    } else {
        (FILE_GENERIC_READ, FILE_NON_DIRECTORY_FILE)
    };
    let mut handle = null_mut();
    let mut io_status = IO_STATUS_BLOCK::default();
    // NtOpenFile receives one counted name relative to the borrowed directory handle.
    let status = unsafe {
        NtOpenFile(
            &mut handle,
            access,
            &attributes,
            &mut io_status,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_REPARSE_POINT | kind,
        )
    };
    if status < 0 {
        // Convert the returned NTSTATUS without consulting thread-local last error.
        return Err(io::Error::from_raw_os_error(
            unsafe { RtlNtStatusToDosError(status) } as i32,
        ));
    }
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
