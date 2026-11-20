use std::{
    collections::HashSet,
    env,
    ffi::OsStr,
    io,
    path::{Component, Path, PathBuf},
    process::{ExitStatus, Stdio},
    time::Duration,
};

use thiserror::Error;
use tokio::{io::AsyncReadExt, process::Command, time};

use crate::checkout::{CheckoutError, CheckoutIdentity};

const TIMEOUT: Duration = Duration::from_secs(8);
const QUERY_BYTES: usize = 512 * 1024;
const PATCH_BYTES: usize = 1024 * 1024;
const MAX_FILES: usize = 2048;
const DIFF_OPTIONS: &[&str] = &[
    "--no-color",
    "--no-ext-diff",
    "--no-textconv",
    "--no-renames",
    "--ignore-submodules=dirty",
];

#[derive(Debug, Error)]
pub enum GitError {
    #[error("Git executable was not found")]
    NotFound,
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error("Git exited with {0}")]
    Exit(ExitStatus),
    #[error("Git did not complete within its query deadline")]
    Timeout,
    #[error("Git output exceeded the checkout change limit")]
    Limit,
    #[error("Git returned unexpected checkout changes")]
    InvalidOutput,
    #[error("the selected changed file no longer resolves inside the checkout")]
    RetiredFile,
}

#[derive(Clone, Debug)]
pub struct GitChange {
    path: PathBuf,
    untracked: bool,
}

impl GitChange {
    pub fn display_path(&self) -> String {
        self.path.to_string_lossy().into_owned()
    }
}

pub struct CheckoutDiff {
    executable: PathBuf,
    checkout: CheckoutIdentity,
    baseline: String,
}

impl CheckoutDiff {
    pub async fn open(checkout: CheckoutIdentity) -> Result<Self, GitError> {
        let executable = discover()?;
        let mut diff = Self {
            executable,
            checkout,
            baseline: String::new(),
        };
        let root = diff
            .success(["rev-parse", "--show-toplevel"], QUERY_BYTES)
            .await?;
        diff.checkout
            .validate_reported(&decode_path(terminated_line(&root)?)?)?;
        let (status, head) = diff
            .run(["rev-parse", "--verify", "--quiet", "HEAD"], QUERY_BYTES)
            .await?;
        let baseline = if status.success() {
            head
        } else if status.code() == Some(1) {
            diff.success(["hash-object", "-t", "tree", "--stdin"], QUERY_BYTES)
                .await?
        } else {
            return Err(GitError::Exit(status));
        };
        let oid = std::str::from_utf8(terminated_line(&baseline)?)
            .map_err(|_| GitError::InvalidOutput)?;
        if !matches!(oid.len(), 40 | 64) || !oid.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(GitError::InvalidOutput);
        }
        diff.baseline = oid.to_owned();
        Ok(diff)
    }

    pub async fn changes(&self) -> Result<Vec<GitChange>, GitError> {
        let tracked = self
            .success(
                ["diff", "--name-status", "-z"]
                    .into_iter()
                    .chain(DIFF_OPTIONS.iter().copied())
                    .chain([self.baseline.as_str(), "--"]),
                QUERY_BYTES,
            )
            .await?;
        let untracked = self
            .success(
                ["ls-files", "--others", "--exclude-standard", "-z", "--"],
                QUERY_BYTES,
            )
            .await?;
        parse_changes(&tracked, &untracked)
    }

    pub async fn patch(&self, change: &GitChange) -> Result<String, GitError> {
        let path = change.path.as_os_str();
        let (status, patch) = if change.untracked {
            self.validate_untracked(&change.path)?;
            let result = self
                .run(
                    ["diff", "--no-index"]
                        .into_iter()
                        .chain(DIFF_OPTIONS.iter().copied())
                        .chain(["--", "/dev/null"])
                        .map(OsStr::new)
                        .chain([path]),
                    PATCH_BYTES,
                )
                .await?;
            self.validate_untracked(&change.path)?;
            result
        } else {
            self.run(
                ["diff"]
                    .into_iter()
                    .chain(DIFF_OPTIONS.iter().copied())
                    .chain([self.baseline.as_str(), "--"])
                    .map(OsStr::new)
                    .chain([path]),
                PATCH_BYTES,
            )
            .await?
        };
        let compared_with_null = change.untracked && status.code() == Some(1);
        if !(status.success() || compared_with_null) {
            return Err(GitError::Exit(status));
        }
        Ok(String::from_utf8_lossy(&patch).into_owned())
    }

    fn validate_untracked(&self, path: &Path) -> Result<(), GitError> {
        let root = self.checkout.canonical_path();
        let full = root.join(path);
        let parent = full.parent().ok_or(GitError::RetiredFile)?.canonicalize()?;
        let kind = full.symlink_metadata()?.file_type();
        if !parent.starts_with(root) || !(kind.is_file() || kind.is_symlink()) {
            return Err(GitError::RetiredFile);
        }
        Ok(())
    }

    async fn success(
        &self,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
        limit: usize,
    ) -> Result<Vec<u8>, GitError> {
        let (status, output) = self.run(args, limit).await?;
        if !status.success() {
            return Err(GitError::Exit(status));
        }
        Ok(output)
    }

    async fn run(
        &self,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
        limit: usize,
    ) -> Result<(ExitStatus, Vec<u8>), GitError> {
        self.checkout.revalidate()?;
        let mut command = Command::new(&self.executable);
        command
            .args(["--no-optional-locks", "--literal-pathspecs", "--no-pager"])
            .args(args)
            .current_dir(self.checkout.canonical_path())
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE")
            .env_remove("GIT_INDEX_FILE")
            .env_remove("GIT_COMMON_DIR")
            .env_remove("GIT_OBJECT_DIRECTORY")
            .env_remove("GIT_ALTERNATE_OBJECT_DIRECTORIES")
            .env_remove("GIT_GLOB_PATHSPECS")
            .env_remove("GIT_NOGLOB_PATHSPECS")
            .env_remove("GIT_ICASE_PATHSPECS")
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_NO_LAZY_FETCH", "1")
            .kill_on_drop(true)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        #[cfg(windows)]
        command.creation_flags(0x08000000);
        let mut child = command.spawn()?;
        let stdout = child.stdout.take().expect("Git stdout is piped");
        let result = time::timeout(TIMEOUT, async {
            let mut output = Vec::new();
            stdout
                .take((limit + 1) as u64)
                .read_to_end(&mut output)
                .await?;
            if output.len() > limit {
                return Err(GitError::Limit);
            }
            let status = child.wait().await?;
            Ok((status, output))
        })
        .await
        .map_err(|_| GitError::Timeout)??;
        self.checkout.revalidate()?;
        Ok(result)
    }
}

fn discover() -> Result<PathBuf, GitError> {
    let inherited = env::var_os("PATH").unwrap_or_default();
    let mut directories = env::split_paths(&inherited).collect::<Vec<_>>();
    #[cfg(unix)]
    directories
        .extend(["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map(PathBuf::from));
    #[cfg(windows)]
    {
        for root in ["ProgramFiles", "ProgramW6432", "LOCALAPPDATA"]
            .into_iter()
            .filter_map(env::var_os)
        {
            let root = PathBuf::from(root);
            directories
                .extend(["Git/cmd", "Git/bin", "Programs/Git/cmd"].map(|path| root.join(path)));
        }
    }
    let name = if cfg!(windows) { "git.exe" } else { "git" };
    directories
        .into_iter()
        .filter(|directory| directory.is_absolute())
        .map(|directory| directory.join(name))
        .find(|path| crate::codex::is_executable(path))
        .ok_or(GitError::NotFound)
}

fn terminated_line(bytes: &[u8]) -> Result<&[u8], GitError> {
    let line = bytes.strip_suffix(b"\n").ok_or(GitError::InvalidOutput)?;
    Ok(if cfg!(windows) {
        line.strip_suffix(b"\r").unwrap_or(line)
    } else {
        line
    })
}

fn parse_changes(tracked: &[u8], untracked: &[u8]) -> Result<Vec<GitChange>, GitError> {
    let mut paths = HashSet::new();
    let mut changes = Vec::new();
    let mut tracked = nul_fields(tracked)?;
    let mut add = |bytes: &[u8], untracked| {
        let path = decode_path(bytes)?;
        if path.as_os_str().is_empty()
            || !path
                .components()
                .all(|part| matches!(part, Component::Normal(_)))
        {
            return Err(GitError::InvalidOutput);
        }
        if paths.insert(path.clone()) {
            if changes.len() == MAX_FILES {
                return Err(GitError::Limit);
            }
            changes.push(GitChange { path, untracked });
        }
        Ok(())
    };
    while let Some(status) = tracked.next() {
        if !matches!(status, b"A" | b"M" | b"D" | b"T" | b"U" | b"X" | b"B") {
            return Err(GitError::InvalidOutput);
        }
        let path = tracked.next().ok_or(GitError::InvalidOutput)?;
        add(path, false)?;
    }
    for path in nul_fields(untracked)? {
        add(path, true)?;
    }
    changes.sort_unstable_by(|left, right| left.path.cmp(&right.path));
    Ok(changes)
}

fn nul_fields(bytes: &[u8]) -> Result<impl Iterator<Item = &[u8]>, GitError> {
    if !bytes.is_empty() && bytes.last() != Some(&0) {
        return Err(GitError::InvalidOutput);
    }
    Ok(bytes
        .split_inclusive(|byte| *byte == 0)
        .map(|field| &field[..field.len() - 1]))
}

#[cfg(unix)]
fn decode_path(bytes: &[u8]) -> Result<PathBuf, GitError> {
    use std::os::unix::ffi::OsStringExt;
    Ok(std::ffi::OsString::from_vec(bytes.to_vec()).into())
}

#[cfg(windows)]
fn decode_path(bytes: &[u8]) -> Result<PathBuf, GitError> {
    Ok(std::str::from_utf8(bytes)
        .map_err(|_| GitError::InvalidOutput)?
        .into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn change_lists_keep_literal_path_records_and_reject_invalid_or_oversized_lists() {
        let tracked = "M\0notes café [draft].txt\0D\0gone.txt\0";
        let files = parse_changes(tracked.as_bytes(), b"new.txt\0gone.txt\0").unwrap();
        assert_eq!(
            files
                .iter()
                .map(GitChange::display_path)
                .collect::<Vec<_>>(),
            ["gone.txt", "new.txt", "notes café [draft].txt"]
        );
        assert!(!files[0].untracked);
        assert!(files[1].untracked);
        assert!(matches!(
            parse_changes(b"M\0../other.txt\0", b""),
            Err(GitError::InvalidOutput)
        ));
        assert!(matches!(
            parse_changes(b"M\0partial.txt", b""),
            Err(GitError::InvalidOutput)
        ));
        let long = (0..=MAX_FILES)
            .map(|index| format!("{index}.txt\0"))
            .collect::<String>();
        assert!(matches!(
            parse_changes(b"", long.as_bytes()),
            Err(GitError::Limit)
        ));
    }
}
