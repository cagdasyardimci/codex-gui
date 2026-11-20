use std::{
    collections::{BTreeSet, BinaryHeap},
    ffi::OsStr,
    fs::File,
    io,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use ts_rs::TS;
use unicode_normalization::UnicodeNormalization;
use unicode_segmentation::UnicodeSegmentation;
use uuid::Uuid;

use super::{CheckoutIdentity, FileError, native};

mod directory;
mod watch;
use directory::EntryKind;
pub use watch::WatchedProjectPaths;

const MAX_FILES: usize = 50_000;
const MAX_VISITED: usize = 250_000;
const MAX_DISCOVERY_BYTES: usize = 24 * 1024 * 1024;
const MAX_DEPTH: usize = 96;
const MAX_RESULTS: usize = 12;
const MAX_QUERY_BYTES: usize = 4_096;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectPathId {
    revision: Uuid,
    entry: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ProjectPathMatch {
    pub id: ProjectPathId,
    pub display_path: String,
}

pub struct ProjectPathIndex {
    checkout: CheckoutIdentity,
    revision: Uuid,
    entries: Vec<Entry>,
    exhaustive: bool,
    limit: usize,
    visited_upper_bound: usize,
    bytes_upper_bound: usize,
}

struct Entry {
    path: PathBuf,
    display: String,
    folded_path: String,
    folded_name: String,
    character_count: usize,
}

impl ProjectPathIndex {
    pub fn scan(checkout: CheckoutIdentity) -> Result<Self, FileError> {
        Self::scan_with_limit(checkout, MAX_FILES)
    }

    fn scan_with_limit(checkout: CheckoutIdentity, limit: usize) -> Result<Self, FileError> {
        checkout.revalidate()?;
        let directory = directory::open_root(&checkout)?;
        let mut scan = Scan::new(limit);
        scan.visit(&directory, &mut PathBuf::new(), 0)?;
        checkout.revalidate()?;
        Ok(Self {
            checkout,
            revision: Uuid::new_v4(),
            entries: scan.paths.into_iter().map(Entry::new).collect(),
            exhaustive: scan.exhaustive,
            limit,
            visited_upper_bound: scan.visited,
            bytes_upper_bound: scan.bytes,
        })
    }

    fn rebuild(&mut self) -> Result<(), FileError> {
        let mut next = Self::scan_with_limit(self.checkout.clone(), self.limit)?;
        if self
            .entries
            .iter()
            .map(|entry| &entry.path)
            .eq(next.entries.iter().map(|entry| &entry.path))
        {
            next.revision = self.revision;
        }
        *self = next;
        Ok(())
    }

    fn refresh_scopes(&mut self, scopes: &BTreeSet<PathBuf>) -> Result<(), FileError> {
        if !self.exhaustive {
            return self.rebuild();
        }
        self.checkout.revalidate()?;
        let root = directory::open_root(&self.checkout)?;
        let mut scan = Scan::new(self.limit);
        for scope in scopes {
            let depth = scope.components().count();
            if depth <= MAX_DEPTH && visible_directory(scope) {
                let Some(dir) = open_scope(&root, scope)? else {
                    continue;
                };
                if !scan.visit(&dir, &mut scope.clone(), depth)? {
                    break;
                }
            }
        }

        let affected = |entry: &Entry| entry.path.ancestors().any(|path| scopes.contains(path));
        let changed = self.entries.iter().filter(|entry| affected(entry));
        let unaffected_count = self.entries.len() - changed.clone().count();
        // A scoped scan cannot subtract work previously spent on omitted names in that scope.
        let visited_upper_bound = self.visited_upper_bound + scan.visited;
        let bytes_upper_bound = self.bytes_upper_bound + scan.bytes;
        if !scan.exhaustive
            || unaffected_count + scan.paths.len() > self.limit
            || visited_upper_bound > MAX_VISITED
            || bytes_upper_bound > MAX_DISCOVERY_BYTES
        {
            return self.rebuild();
        }
        self.checkout.revalidate()?;
        self.visited_upper_bound = visited_upper_bound;
        self.bytes_upper_bound = bytes_upper_bound;
        if changed.map(|entry| &entry.path).eq(scan.paths.iter()) {
            return Ok(());
        }
        self.entries.retain(|entry| !affected(entry));
        self.entries.extend(scan.paths.into_iter().map(Entry::new));
        self.entries
            .sort_unstable_by(|first, second| first.path.cmp(&second.path));
        self.revision = Uuid::new_v4();
        Ok(())
    }

    pub fn search(&self, query: &str) -> Result<Vec<ProjectPathMatch>, FileError> {
        self.checkout.revalidate()?;
        if query.len() > MAX_QUERY_BYTES {
            return Err(FileError::TooLarge);
        }
        let query = search_key(query.trim());
        if query.is_empty() {
            return Ok((0..self.entries.len().min(MAX_RESULTS))
                .map(|index| self.result(index))
                .collect());
        }
        let mut matches = BinaryHeap::with_capacity(MAX_RESULTS);
        for (index, file) in self.entries.iter().enumerate() {
            let Some(score) = file.score(&query) else {
                continue;
            };
            let rank = (score, file.character_count, index);
            if matches.len() < MAX_RESULTS {
                matches.push(rank);
            } else if let Some(mut worst) = matches.peek_mut()
                && rank < *worst
            {
                *worst = rank;
            }
        }
        Ok(matches
            .into_sorted_vec()
            .into_iter()
            .map(|(_, _, index)| self.result(index))
            .collect())
    }

    pub fn relative_path(&self, id: ProjectPathId) -> Result<&Path, FileError> {
        self.checkout.revalidate()?;
        if id.revision != self.revision {
            return Err(FileError::InvalidHandle);
        }
        self.entries
            .get(id.entry as usize)
            .map(|entry| entry.path.as_path())
            .ok_or(FileError::InvalidHandle)
    }

    fn result(&self, index: usize) -> ProjectPathMatch {
        ProjectPathMatch {
            id: ProjectPathId {
                revision: self.revision,
                entry: index as u32,
            },
            display_path: self.entries[index].display.clone(),
        }
    }
}

impl Entry {
    fn new(path: PathBuf) -> Self {
        let display = path
            .iter()
            .map(OsStr::to_string_lossy)
            .collect::<Vec<_>>()
            .join("/");
        Self {
            folded_path: search_key(&display),
            folded_name: search_key(&path.file_name().unwrap().to_string_lossy()),
            character_count: display.graphemes(true).count(),
            path,
            display,
        }
    }

    fn score(&self, query: &str) -> Option<usize> {
        if self.folded_name == query {
            Some(0)
        } else if self.folded_name.starts_with(query) {
            Some(1)
        } else if self.folded_name.contains(query) {
            Some(2)
        } else if self.folded_path.starts_with(query) {
            Some(3)
        } else if self.folded_path.contains(query) {
            Some(4)
        } else {
            None
        }
    }
}

fn search_key(text: &str) -> String {
    if text.is_ascii() {
        return text.to_ascii_lowercase();
    }
    text.to_lowercase().nfc().collect()
}

struct Scan {
    limit: usize,
    paths: BTreeSet<PathBuf>,
    visited: usize,
    bytes: usize,
    exhaustive: bool,
}

impl Scan {
    fn new(limit: usize) -> Self {
        Self {
            limit,
            paths: BTreeSet::new(),
            visited: 0,
            bytes: 0,
            exhaustive: true,
        }
    }

    fn visit(&mut self, dir: &File, relative: &mut PathBuf, depth: usize) -> io::Result<bool> {
        directory::visit(dir, |name, kind| {
            self.visited += 1;
            self.bytes += relative.as_os_str().len() + name.len();
            if self.visited > MAX_VISITED || self.bytes > MAX_DISCOVERY_BYTES {
                self.exhaustive = false;
                return Ok(false);
            }
            if hidden(name) {
                return Ok(true);
            }
            relative.push(name);
            let keep_going = match kind {
                EntryKind::Directory if depth < MAX_DEPTH && !generated_directory(name) => {
                    match open_index_child(dir, name) {
                        Ok(Some(child)) => self.visit(&child, relative, depth + 1)?,
                        Ok(None) => true,
                        Err(_) => {
                            self.exhaustive = false;
                            true
                        }
                    }
                }
                EntryKind::Directory if depth == MAX_DEPTH && !generated_directory(name) => {
                    self.exhaustive = false;
                    true
                }
                EntryKind::File => {
                    if self.paths.len() < self.limit {
                        self.paths.insert(relative.clone());
                    } else {
                        self.exhaustive = false;
                        if self
                            .paths
                            .last()
                            .is_some_and(|last| relative.as_path() < last.as_path())
                        {
                            self.paths.insert(relative.clone());
                            self.paths.pop_last();
                        }
                    }
                    true
                }
                _ => true,
            };
            relative.pop();
            Ok(keep_going)
        })
    }
}

fn open_index_child(dir: &File, name: &OsStr) -> io::Result<Option<File>> {
    match native::open_index_directory(dir, name) {
        Ok(child) => Ok(Some(child)),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::NotFound
                    | io::ErrorKind::NotADirectory
                    | io::ErrorKind::InvalidInput
            ) =>
        {
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

fn open_scope(root: &File, scope: &Path) -> io::Result<Option<File>> {
    let mut directory = None;
    for component in scope.components() {
        let Component::Normal(name) = component else {
            return Err(io::ErrorKind::InvalidInput.into());
        };
        let Some(child) = open_index_child(directory.as_ref().unwrap_or(root), name)? else {
            return Ok(None);
        };
        directory = Some(child);
    }
    Ok(directory)
}

fn visible_directory(path: &Path) -> bool {
    path.iter()
        .all(|name| !hidden(name) && !generated_directory(name))
}

fn hidden(name: &OsStr) -> bool {
    name.as_encoded_bytes().starts_with(b".")
}

fn generated_directory(name: &OsStr) -> bool {
    let name = name.as_encoded_bytes();
    matches!(name, b"node_modules" | b"DerivedData" | b"build" | b"dist")
        || name.ends_with(b".app")
        || name.ends_with(b".xcodeproj")
}

#[cfg(test)]
mod tests;
