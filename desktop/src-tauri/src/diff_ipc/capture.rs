use std::{path::Path, sync::Arc};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    files::{FilePrefix, FileRevision, comparison_file_revision, read_local_file},
    git::{
        CheckoutDiff, ComparisonFileId, GitChange, GitComparison, GitError, turn_edits::TurnEdits,
    },
    ipc::{DiffContentView, DiffFileView, DiffRichKind, DiffSide, FileEditor, FileTabKind},
};

use crate::file_preview_ipc::document_kind;

const CONTENT_LIMIT: usize = 20 * 1024 * 1024;

pub(super) struct Candidate {
    pub path: String,
    pub renamed_from: Option<String>,
    pub source: Source,
}

pub(super) enum Source {
    Tracked(Arc<GitComparison>, ComparisonFileId),
    Untracked(Arc<CheckoutDiff>, GitChange, Option<FileRevision>),
    Reported(Arc<TurnEdits>, usize),
}

pub(super) struct Capture {
    pub marker_origin: String,
    pub patch: Vec<u8>,
    pub patch_exportable: bool,
    pub marks: Vec<String>,
    pub before: Option<Content>,
    pub after: Option<Content>,
}

pub(super) struct Content {
    pub path: String,
    pub bytes: Vec<u8>,
}

impl Candidate {
    pub fn view(&self, file_id: String) -> DiffFileView {
        DiffFileView {
            file_id,
            path: self.path.clone(),
            renamed_from: self.renamed_from.clone(),
        }
    }

    pub async fn capture(
        &self,
        checkout: &CheckoutIdentity,
        origin: &str,
    ) -> Result<Capture, GitError> {
        let (patch, patch_exportable, before, after) = match &self.source {
            Source::Tracked(comparison, file) => {
                let patch = comparison.detail(*file).await?;
                let before = comparison
                    .file_contents(*file, false, CONTENT_LIMIT)
                    .await?;
                let after = comparison.file_contents(*file, true, CONTENT_LIMIT).await?;
                (patch, true, before, after)
            }
            Source::Untracked(comparison, file, revision) => {
                let relative = file.relative();
                let inspected = comparison_file_revision(checkout, relative, CONTENT_LIMIT as u64)?;
                if revision
                    .as_ref()
                    .is_some_and(|expected| expected != &inspected)
                {
                    return Err(GitError::StaleComparison);
                }
                let patch = comparison.patch_bytes(file).await?;
                let after = read_local_file(checkout, relative, CONTENT_LIMIT as u64)
                    .ok()
                    .filter(|read| read.revision == inspected)
                    .map(|read| read.bytes);
                if comparison_file_revision(checkout, relative, CONTENT_LIMIT as u64)? != inspected
                {
                    return Err(GitError::StaleComparison);
                }
                (patch, true, None, after)
            }
            Source::Reported(edits, index) => {
                let file = edits.files.get(*index).ok_or(GitError::RetiredFile)?;
                match edits.file_patch(*index) {
                    Some(patch) => (patch.into_bytes(), true, None, None),
                    None => (file.diff.as_bytes().to_vec(), false, None, None),
                }
            }
        };
        let marker_origin = serde_json::json!([origin, self.renamed_from, self.path]).to_string();
        Ok(Capture {
            marker_origin,
            marks: fingerprints(&patch),
            patch,
            patch_exportable,
            before: before.map(|bytes| Content {
                path: self.renamed_from.as_ref().unwrap_or(&self.path).clone(),
                bytes,
            }),
            after: after.map(|bytes| Content {
                path: self.path.clone(),
                bytes,
            }),
        })
    }
}

impl Capture {
    pub fn contents(&self, side: DiffSide) -> Option<&Content> {
        match side {
            DiffSide::Before => self.before.as_ref(),
            DiffSide::After => self.after.as_ref(),
        }
    }

    pub fn fingerprint(&self, index: i64) -> Option<&str> {
        self.marks
            .get(usize::try_from(index + 1).ok()?)
            .map(String::as_str)
    }
}

impl Content {
    pub fn rich(&self) -> Option<DiffRichKind> {
        let path = Path::new(&self.path);
        let prefix = FilePrefix {
            bytes: self.bytes.iter().copied().take(1024).collect(),
            length: self.bytes.len() as u64,
        };
        match document_kind(path, &prefix) {
            FileTabKind::Pdf => Some(DiffRichKind::Pdf),
            FileTabKind::Raster => Some(DiffRichKind::Raster),
            FileTabKind::Text if self.bytes.len() <= 512 * 1024 => {
                let extension = path.extension()?.to_str()?;
                if extension.eq_ignore_ascii_case("svg") {
                    Some(DiffRichKind::Svg)
                } else if ["md", "markdown"]
                    .iter()
                    .any(|kind| extension.eq_ignore_ascii_case(kind))
                {
                    Some(DiffRichKind::Markdown)
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    pub fn view(&self, side: DiffSide, editors: Vec<FileEditor>) -> DiffContentView {
        let rich = self.rich();
        let text = matches!(rich, Some(DiffRichKind::Markdown | DiffRichKind::Svg))
            .then(|| String::from_utf8(self.bytes.clone()).ok())
            .flatten();
        DiffContentView {
            side,
            path: self.path.clone(),
            rich,
            text,
            editors,
        }
    }
}

fn fingerprints(patch: &[u8]) -> Vec<String> {
    let mut marks = vec![FileRevision::from_bytes(patch).digest];
    let mut start = None;
    let mut offset = 0;
    for line in patch.split_inclusive(|&byte| byte == b'\n') {
        if line.starts_with(b"@@ ")
            && let Some(previous) = start.replace(offset)
        {
            marks.push(FileRevision::from_bytes(&patch[previous..offset]).digest);
        }
        offset += line.len();
    }
    if let Some(start) = start {
        marks.push(FileRevision::from_bytes(&patch[start..]).digest);
    }
    marks
}
