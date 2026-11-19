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
    #[cfg(unix)]
    {
        // Keep executable bytes out of per-test writable files during parallel exec.
        let shim = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/codex-shim.sh");
        fs::write(path.with_extension("script"), contents).unwrap();
        std::os::unix::fs::symlink(shim, &path).unwrap();
    }
    #[cfg(windows)]
    fs::write(&path, contents).unwrap();
    path
}
