use std::{
    fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
pub(super) const SHIM_NAME: &str = "codex";
#[cfg(windows)]
pub(super) const SHIM_NAME: &str = "codex.cmd";

pub(super) fn shim(directory: &Path, contents: &str) -> PathBuf {
    fs::create_dir_all(directory).unwrap();
    let path = directory.join(SHIM_NAME);
    fs::write(&path, contents).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    path
}
