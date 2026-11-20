use std::{fs, io::Read};

use sha2::{Digest, Sha256};

use super::*;

const MAX_ATTRIBUTES_BYTES: u64 = 256 * 1024;
const EFFECTIVE_CONFIG: &str = "^(diff\\.|core\\.(attributesfile|bigfilethreshold|autocrlf|eol|quotepath|filemode|ignorecase)$)";

pub(super) struct PinnedPolicy {
    fingerprint: [u8; 32],
    attributes: Vec<PathBuf>,
}

impl GitComparisons {
    pub(super) async fn pinned_policy(
        &self,
        target: &str,
    ) -> Result<Option<PinnedPolicy>, GitError> {
        let source = attribute_source(target);
        let (status, _) = self
            .git
            .run(
                [source.as_str(), "rev-parse", "--verify", target],
                QUERY_BYTES,
            )
            .await?;
        if !status.success() {
            return Ok(None);
        }

        let info = self
            .git
            .success(
                [
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-path",
                    "info/attributes",
                ],
                QUERY_BYTES,
            )
            .await?;
        let mut attributes = vec![decode_path(terminated_line(&info)?)?];
        for name in ["GIT_ATTR_SYSTEM", "GIT_ATTR_GLOBAL"] {
            let (status, bytes) = self.git.run(["var", name], QUERY_BYTES).await?;
            if status.success() {
                let path = terminated_line(&bytes)?;
                if path.contains(&b'\n') {
                    return Ok(None);
                }
                attributes.push(decode_path(path)?);
            } else if status.code() != Some(1) {
                return Ok(None);
            }
        }
        for path in &mut attributes {
            if !path.is_absolute() {
                *path = self.git.checkout.canonical_path().join(&*path);
            }
        }
        let Some(fingerprint) = self.policy_fingerprint(&attributes).await? else {
            return Ok(None);
        };
        Ok(Some(PinnedPolicy {
            fingerprint,
            attributes,
        }))
    }

    async fn policy_fingerprint(
        &self,
        attributes: &[PathBuf],
    ) -> Result<Option<[u8; 32]>, GitError> {
        let (status, config) = self
            .git
            .run(
                [
                    "config",
                    "--includes",
                    "--null",
                    "--get-regexp",
                    EFFECTIVE_CONFIG,
                ],
                QUERY_BYTES,
            )
            .await?;
        if (!status.success() && status.code() != Some(1))
            || nul_fields(&config)?.any(|record| record.starts_with(b"diff.orderfile\n"))
        {
            return Ok(None);
        }
        let version = self.git.success(["--version"], QUERY_BYTES).await?;
        let mut fingerprint = Sha256::new();
        append(&mut fingerprint, &config);
        append(&mut fingerprint, &version);
        for path in attributes {
            append(&mut fingerprint, path.as_os_str().as_encoded_bytes());
            let metadata = match fs::symlink_metadata(path) {
                Ok(metadata) if metadata.is_file() && metadata.len() <= MAX_ATTRIBUTES_BYTES => {
                    metadata
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    fingerprint.update([0]);
                    continue;
                }
                _ => return Ok(None),
            };
            let file = match open_attribute_file(path) {
                Ok(file) => file,
                Err(_) => return Ok(None),
            };
            if !file.metadata()?.is_file() {
                return Ok(None);
            }
            let mut bytes = Vec::new();
            if file
                .take(MAX_ATTRIBUTES_BYTES + 1)
                .read_to_end(&mut bytes)
                .is_err()
                || bytes.len() as u64 != metadata.len()
            {
                return Ok(None);
            }
            fingerprint.update([1]);
            append(&mut fingerprint, &bytes);
        }
        Ok(Some(fingerprint.finalize().into()))
    }
}

impl PinnedPolicy {
    pub(super) fn fingerprint(&self) -> [u8; 32] {
        self.fingerprint
    }

    pub(super) async fn validate(&self, owner: &GitComparisons) -> Result<(), GitError> {
        if owner.policy_fingerprint(&self.attributes).await? != Some(self.fingerprint) {
            return Err(GitError::StaleComparison);
        }
        Ok(())
    }
}

pub(super) fn attribute_source(target: &str) -> String {
    format!("--attr-source={target}")
}

fn append(hash: &mut Sha256, value: &[u8]) {
    hash.update((value.len() as u64).to_le_bytes());
    hash.update(value);
}

fn open_attribute_file(path: &Path) -> io::Result<fs::File> {
    let mut options = fs::OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_FLAG_OPEN_REPARSE_POINT;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    options.open(path)
}
