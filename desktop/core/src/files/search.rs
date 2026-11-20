//! A search walks one captured project catalog and reads the native checkout in bounded pages.

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use glob::{MatchOptions, Pattern};

use super::*;

const PAGE_MATCHES: usize = 24;
const LIMIT_MATCHES: usize = 480;
const PAGE_FILES: usize = 256;
const PAGE_BYTES: usize = 16 * 1024 * 1024;

pub struct FileContentSearch {
    checkout: CheckoutIdentity,
    candidates: std::vec::IntoIter<(PathBuf, String)>,
    query: String,
    masks: Vec<Pattern>,
    current: Option<CurrentFile>,
    emitted: usize,
}

struct CurrentFile {
    source: Arc<SearchFile>,
    text: String,
    offset: usize,
    line: u32,
}

struct SearchFile {
    relative: PathBuf,
    display: String,
    files: CheckoutFiles,
    link: FileLink,
    revision: FileRevision,
}

#[derive(Clone)]
pub struct ContentMatch {
    source: Arc<SearchFile>,
    pub id: Uuid,
    pub line: u32,
    pub excerpt: String,
}

pub struct ContentPage {
    pub matches: Vec<ContentMatch>,
    pub more: bool,
}

pub struct OpenedSearchFile {
    pub relative: PathBuf,
    pub files: CheckoutFiles,
    pub link: FileLink,
    pub read: FileRead,
    pub line: u32,
}

impl ContentMatch {
    pub fn path(&self) -> &str {
        &self.source.display
    }

    pub fn prepare_open(&self) -> Result<OpenedSearchFile, FileError> {
        let source = &self.source;
        let read = source.files.read_limited(source.link.id, MAX_EDIT_BYTES)?;
        if read.revision != source.revision {
            return Err(FileError::Changed);
        }
        Ok(OpenedSearchFile {
            relative: source.relative.clone(),
            files: source.files.duplicate(source.link.id)?,
            link: source.link.clone(),
            read,
            line: self.line,
        })
    }
}

#[derive(Debug, Error)]
pub enum ContentSearchError {
    #[error("the search has been retired")]
    Canceled,
    #[error("invalid file search query or file type pattern")]
    InvalidQuery,
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
}

impl FileContentSearch {
    pub fn new(
        checkout: CheckoutIdentity,
        candidates: Vec<(PathBuf, String)>,
        query: String,
        mask: &str,
    ) -> Result<Self, ContentSearchError> {
        let query = query.trim();
        if query.is_empty() || query.len() > 1024 || query.contains(['\r', '\n']) {
            return Err(ContentSearchError::InvalidQuery);
        }
        Ok(Self {
            checkout,
            candidates: candidates.into_iter(),
            query: query.to_lowercase(),
            masks: compile_masks(mask)?,
            current: None,
            emitted: 0,
        })
    }

    pub fn next(&mut self, canceled: &AtomicBool) -> Result<ContentPage, ContentSearchError> {
        check_canceled(canceled)?;
        self.checkout.revalidate()?;
        let limit = PAGE_MATCHES.min(LIMIT_MATCHES - self.emitted);
        let mut hits = Vec::with_capacity(limit);
        let (mut visited, mut bytes) = (0, 0);
        while hits.len() < limit {
            check_canceled(canceled)?;
            if let Some(file) = &mut self.current {
                if let Some((source, line, text)) = file.next_line() {
                    if let Some(at) = text.to_lowercase().find(&self.query) {
                        hits.push(ContentMatch {
                            source: source.clone(),
                            id: Uuid::new_v4(),
                            line,
                            excerpt: excerpt(text, at),
                        });
                    }
                    continue;
                }
                self.current = None;
            }
            if visited >= PAGE_FILES || bytes >= PAGE_BYTES {
                break;
            }
            let Some((relative, display)) = self.candidates.next() else {
                break;
            };
            visited += 1;
            if !self.matches_mask(&display) {
                continue;
            }
            if let Some(file) = CurrentFile::read(&self.checkout, relative, display) {
                bytes += file.text.len();
                self.current = Some(file);
            }
        }
        check_canceled(canceled)?;
        self.checkout.revalidate()?;
        self.emitted += hits.len();
        let more = self.emitted < LIMIT_MATCHES
            && (self.current.as_ref().is_some_and(CurrentFile::has_lines)
                || !self.candidates.as_slice().is_empty());
        Ok(ContentPage {
            matches: hits,
            more,
        })
    }

    fn matches_mask(&self, path: &str) -> bool {
        let name = path.rsplit('/').next().unwrap_or(path);
        self.masks.is_empty()
            || self.masks.iter().any(|mask| {
                let target = if mask.as_str().contains('/') {
                    path
                } else {
                    name
                };
                mask.matches_with(
                    target,
                    MatchOptions {
                        case_sensitive: false,
                        require_literal_separator: false,
                        require_literal_leading_dot: false,
                    },
                )
            })
    }
}

impl CurrentFile {
    fn read(checkout: &CheckoutIdentity, relative: PathBuf, display: String) -> Option<Self> {
        let mut files = CheckoutFiles::new(checkout.clone());
        let link = files.issue(&relative).ok()?;
        let read = files.read_limited(link.id, MAX_EDIT_BYTES).ok()?;
        if read.bytes.contains(&0) {
            return None;
        }
        let text = String::from_utf8(read.bytes).ok()?;
        let source = Arc::new(SearchFile {
            relative,
            display,
            files,
            link,
            revision: read.revision,
        });
        Some(Self {
            source,
            text,
            offset: 0,
            line: 1,
        })
    }

    fn next_line(&mut self) -> Option<(&Arc<SearchFile>, u32, &str)> {
        if !self.has_lines() {
            return None;
        }
        let remaining = &self.text[self.offset..];
        let end = remaining.find(['\r', '\n']).unwrap_or(remaining.len());
        let separator = &remaining[end..];
        self.offset += end
            + if separator.starts_with("\r\n") {
                2
            } else {
                usize::from(!separator.is_empty())
            };
        let line = self.line;
        self.line += 1;
        Some((&self.source, line, &remaining[..end]))
    }

    fn has_lines(&self) -> bool {
        self.offset < self.text.len()
    }
}

fn excerpt(line: &str, match_offset: usize) -> String {
    const LENGTH: usize = 220;
    if line.len() <= LENGTH {
        return line.to_owned();
    }
    let center = match_offset.min(line.len());
    let start = line.floor_char_boundary(center.saturating_sub(LENGTH / 3));
    let end = line.floor_char_boundary((start + LENGTH).min(line.len()));
    let prefix = if start > 0 { "…" } else { "" };
    let suffix = if end < line.len() { "…" } else { "" };
    format!("{prefix}{}{suffix}", &line[start..end])
}

fn compile_masks(input: &str) -> Result<Vec<Pattern>, ContentSearchError> {
    let input = input.trim();
    if input.len() > 256 {
        return Err(ContentSearchError::InvalidQuery);
    }
    let masks: Vec<String> = match input.split_once('{').and_then(|(prefix, rest)| {
        rest.split_once('}')
            .map(|(values, suffix)| (prefix, values, suffix))
    }) {
        Some((prefix, values, suffix)) => values
            .split(',')
            .map(|value| format!("{prefix}{}{suffix}", value.trim()))
            .collect(),
        None => input
            .split(',')
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
            .collect(),
    };
    if masks.len() > 32 {
        return Err(ContentSearchError::InvalidQuery);
    }
    masks
        .into_iter()
        .map(|mask| {
            if mask
                .bytes()
                .filter(|character| matches!(character, b'*' | b'?'))
                .count()
                > 8
            {
                return Err(ContentSearchError::InvalidQuery);
            }
            Pattern::new(&mask).map_err(|_| ContentSearchError::InvalidQuery)
        })
        .collect()
}

fn check_canceled(canceled: &AtomicBool) -> Result<(), ContentSearchError> {
    if canceled.load(Ordering::Acquire) {
        return Err(ContentSearchError::Canceled);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_resumes_the_same_file_with_exact_lines_and_a_case_insensitive_mask() {
        let root = tempfile::tempdir().unwrap();
        let text = "header\r\n".to_owned() + &"Café dawn\r".repeat(27);
        fs::write(root.path().join("notes.TXT"), text.as_bytes()).unwrap();
        fs::write(root.path().join("excluded.log"), b"Caf\xc3\xa9 dawn\n").unwrap();
        let checkout = CheckoutIdentity::capture(root.path()).unwrap();
        let mut index = index::WatchedProjectPaths::new(checkout.clone());
        let mut search = FileContentSearch::new(
            checkout,
            index.content_candidates().unwrap(),
            "CAFÉ dawn".into(),
            "*.{txt,md}",
        )
        .unwrap();
        let canceled = AtomicBool::new(false);
        let first = search.next(&canceled).unwrap();
        assert!(first.more);
        assert_eq!(first.matches.len(), PAGE_MATCHES);
        assert_eq!(first.matches[0].line, 2);
        let second = search.next(&canceled).unwrap();
        assert!(!second.more);
        assert_eq!(
            second
                .matches
                .iter()
                .map(|item| item.line)
                .collect::<Vec<_>>(),
            vec![26, 27, 28]
        );
        let matched = &second.matches[0];
        assert_eq!(
            (matched.path(), matched.excerpt.as_str()),
            ("notes.TXT", "Café dawn")
        );
        assert_eq!(matched.prepare_open().unwrap().read.bytes, text.as_bytes());

        fs::rename(root.path().join("notes.TXT"), root.path().join("old.TXT")).unwrap();
        fs::write(root.path().join("notes.TXT"), text).unwrap();
        assert!(matches!(matched.prepare_open(), Err(FileError::Replaced)));
        canceled.store(true, Ordering::Release);
        assert!(matches!(
            search.next(&canceled),
            Err(ContentSearchError::Canceled)
        ));
    }
}
