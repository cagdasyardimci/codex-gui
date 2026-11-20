use super::*;

#[derive(Debug, Eq, PartialEq)]
pub(super) struct RawChange {
    identity: Vec<u8>,
    pub(super) kind: ComparisonKind,
    pub(super) before: Option<PathBuf>,
    pub(super) after: Option<PathBuf>,
}

impl RawChange {
    pub(super) fn is_gitlink(&self) -> bool {
        self.identity.split(|&byte| byte == b' ').nth(1) == Some(b"160000")
    }
}

pub(super) fn parse_changes(bytes: &[u8]) -> Result<Vec<RawChange>, GitError> {
    use ComparisonKind::*;
    let mut fields = nul_fields(bytes)?;
    let mut files = Vec::new();
    while let Some(header) = fields.next() {
        let status = header
            .rsplit(|&byte| byte == b' ')
            .next()
            .ok_or(GitError::InvalidOutput)?;
        if header.first() != Some(&b':') || status.is_empty() {
            return Err(GitError::InvalidOutput);
        }
        let path = decode_relative_path(fields.next().ok_or(GitError::InvalidOutput)?)?;
        let (kind, before, after) = match status[0] {
            b'A' => (Added, None, Some(path)),
            b'D' => (Deleted, Some(path), None),
            b'M' | b'T' => (Modified, Some(path.clone()), Some(path)),
            b'R' | b'C' => {
                let target = decode_relative_path(fields.next().ok_or(GitError::InvalidOutput)?)?;
                let kind = if status[0] == b'R' { Renamed } else { Copied };
                (kind, Some(path), Some(target))
            }
            b'U' => return Err(GitError::UnmergedIndex),
            _ => return Err(GitError::InvalidOutput),
        };
        if files.len() == MAX_FILES {
            return Err(GitError::Limit);
        }
        files.push(RawChange {
            identity: header.to_vec(),
            kind,
            before,
            after,
        });
    }
    Ok(files)
}

pub(super) fn patch_sections(output: &[u8]) -> Result<(Vec<RawChange>, Vec<&[u8]>), GitError> {
    if output.is_empty() {
        return Ok((Vec::new(), Vec::new()));
    }
    let split = output
        .windows(2)
        .position(|bytes| bytes == b"\0\0")
        .ok_or(GitError::InvalidOutput)?;
    let changes = parse_changes(&output[..=split])?;
    let patch = &output[split + 2..];
    if !patch.starts_with(b"diff --git ") {
        return Err(GitError::InvalidOutput);
    }
    let mut offset = 0;
    let mut starts = Vec::new();
    for line in patch.split_inclusive(|&byte| byte == b'\n') {
        // Patch content always has a leading indicator, including context lines.
        if line.starts_with(b"diff --git ") {
            starts.push(offset);
        }
        offset += line.len();
    }
    if starts.len() != changes.len() {
        return Err(GitError::InvalidOutput);
    }
    starts.push(patch.len());
    Ok((
        changes,
        starts
            .windows(2)
            .map(|bounds| &patch[bounds[0]..bounds[1]])
            .collect(),
    ))
}
