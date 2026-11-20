use std::{
    ffi::OsString,
    sync::{Arc, Mutex},
};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::*;
use crate::files::FileRevision;

mod cache;
mod export;
mod policy;
mod raw;
mod selectors;
use cache::{ComparisonCache, ImmutableKey, ReusableComparison};
use policy::{PinnedPolicy, attribute_source};
use raw::{RawChange, parse_changes as parse_raw_changes, patch_sections};
pub use selectors::{BranchChoice, BranchSelectors, RecentCommit};

const COMPARISON_PATCH_BYTES: usize = 8 * 1024 * 1024;
const PATCH_ARGUMENTS: [&str; 3] = ["--patch", "--binary", "--unified=2147483647"];
const DIFF_ARGUMENTS: &[&str] = &[
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--no-textconv",
    "--full-index",
    "--no-abbrev",
    "--find-renames",
    "--find-copies",
    "--ignore-submodules=none",
    "--submodule=short",
    "--no-relative",
    "--src-prefix=a/",
    "--dst-prefix=b/",
    "--line-prefix=",
    "--output-indicator-new=+",
    "--output-indicator-old=-",
    "--output-indicator-context= ",
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ComparisonSpec {
    Uncommitted,
    Unstaged,
    Staged,
    WorkingTreeAgainstBranch(Option<String>),
    Between { base: String, target: String },
    Commit(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ComparisonSide {
    Object(String),
    Index,
    WorkingTree,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
pub struct ComparisonFileId(Uuid);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ComparisonKind {
    Added,
    Deleted,
    Modified,
    Renamed,
    Copied,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ComparisonFile {
    pub id: ComparisonFileId,
    pub before: Option<String>,
    pub after: Option<String>,
    pub kind: ComparisonKind,
}

#[derive(Clone)]
pub struct GitComparisons {
    git: Arc<CheckoutGit>,
    repository: CheckoutIdentity,
    cache: Arc<Mutex<ComparisonCache>>,
}

pub struct GitComparison {
    owner: GitComparisons,
    base: ComparisonSide,
    target: ComparisonSide,
    policy: Vec<OsString>,
    pinned: Option<PinnedPolicy>,
    entries: Arc<[Entry]>,
    shared: Option<Arc<ReusableComparison>>,
}

struct Entry {
    id: ComparisonFileId,
    change: RawChange,
    input: Option<FileRevision>,
}

impl GitComparisons {
    pub async fn open(checkout: CheckoutIdentity) -> Result<Self, GitError> {
        let git = Arc::new(CheckoutGit::new(checkout)?);
        let repository = git.repository_identity().await?;
        Ok(Self {
            git,
            repository,
            cache: Arc::default(),
        })
    }

    pub async fn compare(&self, spec: ComparisonSpec) -> Result<GitComparison, GitError> {
        self.verify_repository().await?;
        let (base, target) = self.resolve(spec).await?;
        let mut policy = self.diff_policy().await?;
        let mut key = None;
        let mut pinned = None;
        if let (ComparisonSide::Object(base), ComparisonSide::Object(target)) = (&base, &target)
            && let Some(snapshot) = self.pinned_policy(target).await?
        {
            key = Some(ImmutableKey {
                base: base.clone(),
                target: target.clone(),
                policy: snapshot.fingerprint(),
            });
            policy.push(attribute_source(target).into());
            policy.push("--no-replace-objects".into());
            pinned = Some(snapshot);
        }
        let mut comparison = GitComparison {
            owner: self.clone(),
            base,
            target,
            policy,
            pinned,
            entries: Arc::from([]),
            shared: None,
        };
        if let Some(key) = &key
            && let Some(shared) = self
                .cache
                .lock()
                .expect("comparison cache poisoned")
                .get(key)
        {
            comparison.entries = shared.files.clone();
            comparison.shared = Some(shared);
            return Ok(comparison);
        }
        comparison.entries = comparison.capture_entries().await?.into();
        if comparison.is_mutable() {
            comparison.verify_summary().await?;
        }
        self.verify_repository().await?;
        comparison.verify_pinned_policy().await?;
        if let Some(key) = key {
            let shared = self
                .cache
                .lock()
                .expect("comparison cache poisoned")
                .share(key, comparison.entries);
            comparison.entries = shared.files.clone();
            comparison.shared = Some(shared);
        }
        Ok(comparison)
    }

    async fn verify_repository(&self) -> Result<(), GitError> {
        if self.git.repository_identity().await? != self.repository {
            return Err(GitError::StaleComparison);
        }
        Ok(())
    }

    async fn resolve(
        &self,
        spec: ComparisonSpec,
    ) -> Result<(ComparisonSide, ComparisonSide), GitError> {
        use ComparisonSide::{Index, Object, WorkingTree};
        Ok(match spec {
            ComparisonSpec::Uncommitted => (Object(self.head_or_empty().await?), WorkingTree),
            ComparisonSpec::Staged => (Object(self.head_or_empty().await?), Index),
            ComparisonSpec::Unstaged => (Index, WorkingTree),
            ComparisonSpec::WorkingTreeAgainstBranch(branch) => {
                let branch = match branch {
                    Some(branch) => branch,
                    None => self
                        .branches()
                        .await?
                        .upstream
                        .unwrap_or_else(|| "HEAD".into()),
                };
                (Object(self.resolve_commit(&branch).await?), WorkingTree)
            }
            ComparisonSpec::Between { base, target } => (
                Object(self.resolve_commit(&base).await?),
                Object(self.resolve_commit(&target).await?),
            ),
            ComparisonSpec::Commit(revision) => {
                let target = self.resolve_commit(&revision).await?;
                let lineage = self
                    .git
                    .success(
                        [
                            "--no-replace-objects",
                            "rev-list",
                            "--parents",
                            "-1",
                            &target,
                            "--",
                        ],
                        QUERY_BYTES,
                    )
                    .await?;
                let mut commits = terminated_line(&lineage)?.split(|&byte| byte == b' ');
                if commits.next() != Some(target.as_bytes()) {
                    return Err(GitError::InvalidOutput);
                }
                let base = if let Some(parent) = commits.next() {
                    parse_object_id(parent)?.to_owned()
                } else {
                    self.empty_tree().await?
                };
                (Object(base), Object(target))
            }
        })
    }

    async fn resolve_commit(&self, reference: &str) -> Result<String, GitError> {
        if reference.is_empty() || reference.contains('\0') {
            return Err(GitError::InvalidRevision);
        }
        let commit = format!("{reference}^{{commit}}");
        let (status, bytes) = self
            .git
            .run(
                [
                    "--no-replace-objects",
                    "rev-parse",
                    "--verify",
                    "--end-of-options",
                    &commit,
                ],
                QUERY_BYTES,
            )
            .await?;
        if !status.success() {
            return Err(GitError::InvalidRevision);
        }
        Ok(parse_oid(&bytes)?.to_owned())
    }

    async fn head_or_empty(&self) -> Result<String, GitError> {
        let (status, bytes) = self
            .git
            .run(
                ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
                QUERY_BYTES,
            )
            .await?;
        if status.success() {
            Ok(parse_oid(&bytes)?.to_owned())
        } else if status.code() == Some(1) {
            self.empty_tree().await
        } else {
            Err(GitError::Exit(status))
        }
    }

    async fn empty_tree(&self) -> Result<String, GitError> {
        let bytes = self
            .git
            .success(["hash-object", "-t", "tree", "--stdin"], QUERY_BYTES)
            .await?;
        Ok(parse_oid(&bytes)?.to_owned())
    }

    async fn diff_policy(&self) -> Result<Vec<OsString>, GitError> {
        let (status, keys) = self
            .git
            .run(
                [
                    "config",
                    "--includes",
                    "--null",
                    "--name-only",
                    "--get-regexp",
                    "^filter\\.",
                ],
                QUERY_BYTES,
            )
            .await?;
        if !status.success() && status.code() != Some(1) {
            return Err(GitError::Exit(status));
        }
        let mut args = ["-c", "core.fsmonitor=false", "-c", "core.quotePath=true"]
            .map(OsString::from)
            .to_vec();
        let mut drivers = HashSet::new();
        for key in nul_fields(&keys)? {
            let index = key
                .iter()
                .rposition(|&byte| byte == b'.')
                .ok_or(GitError::InvalidOutput)?;
            if drivers.insert(&key[..index]) {
                for suffix in [".clean=", ".smudge=", ".process=", ".required=false"] {
                    let mut driver = decode_path(&key[..index])?.into_os_string();
                    driver.push(suffix);
                    args.push("-c".into());
                    args.push(driver);
                }
            }
        }
        Ok(args)
    }
}

impl GitComparison {
    pub fn sides(&self) -> (&ComparisonSide, &ComparisonSide) {
        (&self.base, &self.target)
    }

    pub fn files(&self) -> impl ExactSizeIterator<Item = ComparisonFile> + '_ {
        self.entries.iter().map(|entry| ComparisonFile {
            id: entry.id,
            kind: entry.change.kind,
            before: entry
                .change
                .before
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned()),
            after: entry
                .change
                .after
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned()),
        })
    }

    pub async fn detail(&self, id: ComparisonFileId) -> Result<Vec<u8>, GitError> {
        let entry = self
            .entries
            .iter()
            .find(|entry| entry.id == id)
            .ok_or(GitError::RetiredFile)?;
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        if let Some(bytes) = self
            .shared
            .as_ref()
            .and_then(|shared| shared.get_patch(Some(id)))
        {
            return Ok(bytes.to_vec());
        }
        self.verify_entry(entry).await?;
        let before = entry.change.before.as_ref();
        let paths = before
            .into_iter()
            .chain(
                entry
                    .change
                    .after
                    .iter()
                    .filter(|path| before != Some(*path)),
            )
            .map(|path| path.as_os_str());
        let output = self
            .diff(
                ["--raw", "-z"].into_iter().chain(PATCH_ARGUMENTS),
                paths,
                COMPARISON_PATCH_BYTES,
            )
            .await?;
        self.owner.verify_repository().await?;
        self.verify_pinned_policy().await?;
        self.verify_entry(entry).await?;
        let (changes, sections) = patch_sections(&output)?;
        let section = changes
            .iter()
            .zip(sections)
            .find_map(|(change, bytes)| (change == &entry.change).then_some(bytes))
            .ok_or(GitError::StaleComparison)?;
        if let Some(shared) = &self.shared {
            shared.store_patch(Some(id), section);
        }
        Ok(section.to_vec())
    }

    async fn verify_pinned_policy(&self) -> Result<(), GitError> {
        if let Some(pinned) = &self.pinned {
            pinned.validate(&self.owner).await?;
        }
        Ok(())
    }

    async fn read_summary(&self) -> Result<Vec<RawChange>, GitError> {
        let raw = self
            .diff(["--raw", "-z"], std::iter::empty(), QUERY_BYTES)
            .await?;
        parse_raw_changes(&raw)
    }

    async fn diff<'path>(
        &'path self,
        output: impl IntoIterator<Item = &'path str>,
        paths: impl Iterator<Item = &'path OsStr>,
        limit: usize,
    ) -> Result<Vec<u8>, GitError> {
        let refs = [&self.base, &self.target]
            .into_iter()
            .filter_map(|side| match side {
                ComparisonSide::Object(oid) => Some(OsStr::new(oid)),
                _ => None,
            });
        self.owner
            .git
            .success(
                self.policy
                    .iter()
                    .map(OsString::as_os_str)
                    .chain(DIFF_ARGUMENTS.iter().copied().map(OsStr::new))
                    .chain(
                        matches!(self.target, ComparisonSide::Index)
                            .then_some(OsStr::new("--cached")),
                    )
                    .chain(output.into_iter().map(OsStr::new))
                    .chain(refs)
                    .chain([OsStr::new("--")])
                    .chain(paths),
                limit,
            )
            .await
    }
}

#[cfg(test)]
mod tests;
