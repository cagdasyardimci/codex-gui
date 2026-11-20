use super::*;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BranchChoice {
    pub reference: String,
    pub label: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BranchSelectors {
    pub current: Option<String>,
    pub upstream: Option<String>,
    pub choices: Vec<BranchChoice>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RecentCommit {
    pub oid: String,
    pub subject: String,
    pub committed_at: i64,
}

impl GitComparisons {
    pub async fn branches(&self) -> Result<BranchSelectors, GitError> {
        self.verify_repository().await?;
        let bytes = self
            .git
            .success(
                [
                    "for-each-ref",
                    "--sort=refname",
                    "--format=%(refname)%00%(refname:short)%00%(symref)%00%(HEAD)%00%(upstream)",
                    "refs/heads",
                    "refs/remotes",
                ],
                QUERY_BYTES,
            )
            .await?;
        let mut result = BranchSelectors {
            current: None,
            upstream: None,
            choices: Vec::new(),
        };
        for line in bytes.split_inclusive(|&byte| byte == b'\n') {
            let line = terminated_line(line)?;
            let fields: Vec<_> = line.split(|&byte| byte == 0).collect();
            let [reference, label, symbolic, head, upstream] = fields.as_slice() else {
                return Err(GitError::InvalidOutput);
            };
            if !symbolic.is_empty() {
                continue;
            }
            let reference = std::str::from_utf8(reference).map_err(|_| GitError::InvalidOutput)?;
            if *head == b"*" {
                result.current = Some(reference.to_owned());
                if !upstream.is_empty() {
                    result.upstream = Some(
                        std::str::from_utf8(upstream)
                            .map_err(|_| GitError::InvalidOutput)?
                            .to_owned(),
                    );
                }
            } else {
                result.choices.push(BranchChoice {
                    reference: reference.to_owned(),
                    label: String::from_utf8_lossy(label).into_owned(),
                });
            }
        }
        self.verify_repository().await?;
        Ok(result)
    }

    pub async fn recent_commits(&self) -> Result<Vec<RecentCommit>, GitError> {
        self.verify_repository().await?;
        let (status, head) = self
            .git
            .run(
                ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
                QUERY_BYTES,
            )
            .await?;
        if status.code() == Some(1) {
            return Ok(Vec::new());
        }
        if !status.success() {
            return Err(GitError::Exit(status));
        }
        let commit = parse_oid(&head)?;
        let result = self
            .git
            .success(
                ["log", "-5", "-z", "--format=%H%x00%ct%x00%s", commit, "--"],
                QUERY_BYTES,
            )
            .await?;
        let mut fields = nul_fields(&result)?;
        let mut commits = Vec::new();
        while let Some(oid) = fields.next() {
            let oid = parse_object_id(oid)?.to_owned();
            let date = fields.next().ok_or(GitError::InvalidOutput)?;
            let committed_at = std::str::from_utf8(date)
                .map_err(|_| GitError::InvalidOutput)?
                .parse()
                .map_err(|_| GitError::InvalidOutput)?;
            let subject = fields.next().ok_or(GitError::InvalidOutput)?;
            let subject = String::from_utf8_lossy(subject)
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ");
            commits.push(RecentCommit {
                subject: if subject.is_empty() {
                    oid[..12].to_owned()
                } else {
                    subject
                },
                oid,
                committed_at,
            });
        }
        self.verify_repository().await?;
        Ok(commits)
    }
}
