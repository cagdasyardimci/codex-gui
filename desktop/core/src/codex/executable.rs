use std::{
    env,
    ffi::OsString,
    io,
    path::{Path, PathBuf},
    process::{ExitStatus, Stdio},
    time::Duration,
};

use thiserror::Error;
use tokio::{io::AsyncReadExt, process::Command, time};

const MAX_VERSION_BYTES: usize = 4 * 1024;

#[cfg(unix)]
const CODEX_NAMES: &[&str] = &["codex"];
#[cfg(windows)]
const CODEX_NAMES: &[&str] = &["codex.exe", "codex.cmd", "codex.bat"];

#[derive(Debug, Error)]
pub enum DiscoveryError {
    #[error("Codex executable override must name an absolute executable path: {0}")]
    InvalidOverride(PathBuf),
    #[error("Codex executable was not found")]
    NotFound,
    #[error("could not construct the Codex process PATH: {0}")]
    InvalidSearchPath(#[from] env::JoinPathsError),
}

#[derive(Debug, Error)]
pub enum VersionProbeError {
    #[error("could not run the Codex version probe: {0}")]
    Io(#[from] io::Error),
    #[error("Codex version probe exited with {0}")]
    Exit(ExitStatus),
    #[error("Codex version probe timed out")]
    Timeout,
    #[error("Codex version output exceeded the byte limit")]
    Oversized,
    #[error("Codex version output was empty or invalid UTF-8")]
    InvalidOutput,
}

#[derive(Debug)]
pub struct CodexExecutable {
    path: PathBuf,
    search_path: OsString,
}

impl CodexExecutable {
    pub fn discover(override_path: Option<&Path>) -> Result<Self, DiscoveryError> {
        Self::discover_with(override_path, |name| env::var_os(name))
    }

    fn discover_with(
        override_path: Option<&Path>,
        lookup: impl Fn(&str) -> Option<OsString>,
    ) -> Result<Self, DiscoveryError> {
        let environment_override = lookup("CODEX_EXECUTABLE");
        let override_path = override_path.or(environment_override.as_deref().map(Path::new));
        if let Some(path) = override_path
            && (!path.is_absolute() || !is_executable(path))
        {
            return Err(DiscoveryError::InvalidOverride(path.to_path_buf()));
        }

        let inherited = lookup("PATH").unwrap_or_default();
        let inherited_dirs: Vec<_> = env::split_paths(&inherited).collect();
        let launcher_dirs = launcher_directories(&lookup);
        let path = match override_path {
            Some(path) => path.to_path_buf(),
            None => inherited_dirs
                .iter()
                .chain(&launcher_dirs)
                .filter(|dir| dir.is_absolute())
                .flat_map(|directory| CODEX_NAMES.iter().map(move |name| directory.join(name)))
                .find(|candidate| is_executable(candidate))
                .ok_or(DiscoveryError::NotFound)?,
        };
        // An npm shim may need a sibling Node executable when launched with a sparse PATH.
        let search_path = env::join_paths(
            path.parent()
                .into_iter()
                .chain(inherited_dirs.iter().map(PathBuf::as_path))
                .chain(launcher_dirs.iter().map(PathBuf::as_path))
                .filter(|dir| dir.is_absolute()),
        )?;
        Ok(Self { path, search_path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn command(&self) -> Command {
        let mut command = Command::new(&self.path);
        command.env("PATH", &self.search_path);
        command.kill_on_drop(true);
        command
    }

    pub async fn probe_version(&self, timeout: Duration) -> Result<String, VersionProbeError> {
        let mut child = self
            .command()
            .arg("--version")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let stdout = child.stdout.take().expect("version stdout is piped");
        let probe = async {
            let mut output = Vec::new();
            stdout
                .take((MAX_VERSION_BYTES + 1) as u64)
                .read_to_end(&mut output)
                .await?;
            if output.len() > MAX_VERSION_BYTES {
                return Err(VersionProbeError::Oversized);
            }
            let status = child.wait().await?;
            if !status.success() {
                return Err(VersionProbeError::Exit(status));
            }
            let version = std::str::from_utf8(&output)
                .map_err(|_| VersionProbeError::InvalidOutput)?
                .trim();
            if version.is_empty() {
                return Err(VersionProbeError::InvalidOutput);
            }
            Ok(version.to_owned())
        };
        time::timeout(timeout, probe)
            .await
            .map_err(|_| VersionProbeError::Timeout)?
    }
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;

    std::fs::metadata(path)
        .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(windows)]
fn is_executable(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            ["exe", "cmd", "bat"]
                .iter()
                .any(|allowed| extension.eq_ignore_ascii_case(allowed))
        })
        && path.is_file()
}

#[cfg(unix)]
fn launcher_directories(lookup: &impl Fn(&str) -> Option<OsString>) -> Vec<PathBuf> {
    use std::cmp::Reverse;

    let home = lookup("HOME").map(PathBuf::from);
    let mut dirs = Vec::new();
    if cfg!(target_os = "macos") {
        dirs.push(PathBuf::from("/opt/homebrew/bin"));
    }
    dirs.push(PathBuf::from("/usr/local/bin"));
    dirs.extend(lookup("PNPM_HOME").map(PathBuf::from));
    if let Some(home) = &home {
        dirs.extend([".local/bin", ".cargo/bin", ".volta/bin"].map(|relative| home.join(relative)));
    }
    let nvm = lookup("NVM_DIR")
        .map(PathBuf::from)
        .or_else(|| home.map(|home| home.join(".nvm")));
    if let Some(nvm) = nvm.filter(|path| path.is_absolute()) {
        dirs.push(nvm.join("current/bin"));
        if let Ok(installed) = std::fs::read_dir(nvm.join("versions/node")) {
            let mut versions: Vec<_> = installed
                .filter_map(Result::ok)
                .filter_map(|entry| {
                    let name = entry.file_name();
                    let version = semver::Version::parse(name.to_str()?.strip_prefix('v')?).ok()?;
                    Some((Reverse(version), entry.path().join("bin")))
                })
                .collect();
            versions.sort();
            dirs.extend(versions.into_iter().map(|(_, path)| path));
        }
    }
    dirs.push(PathBuf::from("/usr/bin"));
    dirs
}

#[cfg(windows)]
fn launcher_directories(lookup: &impl Fn(&str) -> Option<OsString>) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    dirs.extend(lookup("PNPM_HOME").map(PathBuf::from));
    dirs.extend(lookup("NVM_SYMLINK").map(PathBuf::from));
    if let Some(program_files) = lookup("ProgramFiles").map(PathBuf::from) {
        dirs.push(program_files.join("nodejs"));
    }
    if let Some(app_data) = lookup("APPDATA").map(PathBuf::from) {
        dirs.push(app_data.join("npm"));
    }
    if let Some(local) = lookup("LOCALAPPDATA").map(PathBuf::from) {
        dirs.push(local.join("Microsoft/WinGet/Links"));
    }
    dirs
}

#[cfg(test)]
#[path = "executable_tests.rs"]
mod tests;
