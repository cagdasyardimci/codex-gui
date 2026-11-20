use std::{
    path::{Component, Path, PathBuf},
    sync::Arc,
};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use ts_rs::TS;
use uuid::Uuid;

use crate::{checkout::CheckoutIdentity, identity::TurnId};

mod composition;
mod reports;
pub use reports::TurnEditReports;

use composition::compose;

const MAX_REPORT_BYTES: usize = 2 * 1024 * 1024;
const MAX_REPORTED_FILES: usize = 512;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum TurnEditQuality {
    Missing,
    Exact,
    Reported,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct EditTotals {
    pub additions: u32,
    pub deletions: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct LastTurnView {
    pub turn_id: String,
    pub revision: Option<Uuid>,
    pub quality: TurnEditQuality,
    pub totals: Option<EditTotals>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TurnFileEdit {
    pub before: Option<PathBuf>,
    pub after: Option<PathBuf>,
    pub diff: String,
    pub totals: EditTotals,
}

#[derive(Debug)]
pub struct TurnEdits {
    view: LastTurnView,
    pub files: Vec<TurnFileEdit>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ReportedEdit {
    path: PathBuf,
    kind: EditKind,
    destination: Option<PathBuf>,
    diff: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "lowercase")]
enum EditKind {
    Add,
    Delete,
    Update,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct ReportItem {
    terminal: bool,
    incomplete: bool,
    edits: Vec<ReportedEdit>,
}

#[derive(Deserialize)]
struct WireEdit<'a> {
    path: &'a str,
    kind: WireKind<'a>,
    diff: &'a str,
}

#[derive(Deserialize)]
struct WireKind<'a> {
    #[serde(rename = "type")]
    kind: EditKind,
    move_path: Option<&'a str>,
}

impl ReportItem {
    fn read(checkout: &CheckoutIdentity, wire: &Value, terminal: bool, incomplete: bool) -> Self {
        let Some(changes) = wire.as_array() else {
            return Self {
                terminal,
                incomplete: true,
                edits: Vec::new(),
            };
        };
        let mut result = Self {
            terminal,
            incomplete,
            edits: Vec::new(),
        };
        let mut used = 0;
        for change in changes {
            if result.edits.len() == MAX_REPORTED_FILES {
                result.incomplete = true;
                break;
            }
            let Ok(change) = WireEdit::deserialize(change) else {
                result.incomplete = true;
                continue;
            };
            let Some(path) = relative_path(checkout, change.path) else {
                continue;
            };
            let destination = match change.kind.move_path {
                Some(target) => {
                    let Some(target) = relative_path(checkout, target) else {
                        continue;
                    };
                    (target != path).then_some(target)
                }
                None => None,
            };
            used +=
                change.diff.len() + change.path.len() + change.kind.move_path.map_or(0, str::len);
            if used > MAX_REPORT_BYTES {
                result.incomplete = true;
                break;
            }
            result.edits.push(ReportedEdit {
                path,
                kind: change.kind.kind,
                destination,
                diff: change.diff.to_owned(),
            });
        }
        result
    }

    fn bytes(&self) -> usize {
        self.edits
            .iter()
            .map(|edit| {
                edit.path.as_os_str().len()
                    + edit
                        .destination
                        .as_ref()
                        .map_or(0, |path| path.as_os_str().len())
                    + edit.diff.len()
            })
            .sum()
    }
}

impl TurnEdits {
    pub fn view(&self) -> &LastTurnView {
        &self.view
    }

    pub fn applicable_patch(&self) -> Option<String> {
        if self.view.quality != TurnEditQuality::Exact {
            return None;
        }
        let mut patch = String::new();
        for file in &self.files {
            append_patch(&mut patch, file)?;
        }
        (patch.len() <= 8 * 1024 * 1024).then_some(patch)
    }

    pub fn file_patch(&self, index: usize) -> Option<String> {
        if self.view.quality != TurnEditQuality::Exact {
            return None;
        }
        let mut patch = String::new();
        append_patch(&mut patch, self.files.get(index)?)?;
        (patch.len() <= 8 * 1024 * 1024).then_some(patch)
    }

    fn build<'report>(
        turn: &TurnId,
        items: impl Iterator<Item = &'report ReportItem>,
        partial: bool,
    ) -> Arc<Self> {
        let mut exact = !partial;
        let mut edits = Vec::new();
        for item in items {
            exact &= !item.incomplete;
            edits.extend(item.edits.iter());
        }
        let (files, composed) = compose(&edits);
        let totals = files.iter().fold(EditTotals::default(), |mut sum, file| {
            sum.additions += file.totals.additions;
            sum.deletions += file.totals.deletions;
            sum
        });
        Arc::new(Self {
            view: LastTurnView {
                turn_id: turn.0.clone(),
                revision: Some(Uuid::new_v4()),
                quality: if exact && composed {
                    TurnEditQuality::Exact
                } else {
                    TurnEditQuality::Reported
                },
                totals: Some(totals),
            },
            files,
        })
    }
}

fn append_patch(patch: &mut String, file: &TurnFileEdit) -> Option<()> {
    let old = file.before.as_ref().or(file.after.as_ref())?;
    let new = file.after.as_ref().or(file.before.as_ref())?;
    let old_name = old.to_str()?;
    let new_name = new.to_str()?;
    #[cfg(windows)]
    let (old_name, new_name) = (
        &old_name.replace('\\', "/")[..],
        &new_name.replace('\\', "/")[..],
    );
    patch.push_str(&format!(
        "diff --git {} {}\n",
        quoted("a/", old_name),
        quoted("b/", new_name)
    ));
    if file.before.is_none() {
        patch.push_str("new file mode 100644\n");
    } else if file.after.is_none() {
        patch.push_str("deleted file mode 100644\n");
    } else if old != new {
        patch.push_str(&format!(
            "rename from {}\nrename to {}\n",
            quoted("", old_name),
            quoted("", new_name)
        ));
    }
    if !file.diff.is_empty() {
        let from = file
            .before
            .as_ref()
            .map_or_else(|| "/dev/null".into(), |_| quoted("a/", old_name));
        let to = file
            .after
            .as_ref()
            .map_or_else(|| "/dev/null".into(), |_| quoted("b/", new_name));
        patch.push_str(&format!("--- {from}\n+++ {to}\n{}\n", file.diff));
    }
    Some(())
}

impl TurnFileEdit {
    fn new(before: Option<PathBuf>, after: Option<PathBuf>, diff: String) -> Self {
        let mut totals = EditTotals::default();
        let mut in_hunk = false;
        for line in diff.split_terminator('\n') {
            if line.starts_with("@@ ") {
                in_hunk = true;
            } else if line.starts_with("diff --git ") {
                in_hunk = false;
            } else if in_hunk {
                match line.as_bytes().first() {
                    Some(b'+') => totals.additions += 1,
                    Some(b'-') => totals.deletions += 1,
                    _ => {}
                }
            }
        }
        Self {
            before,
            after,
            diff,
            totals,
        }
    }
}

fn relative_path(checkout: &CheckoutIdentity, value: &str) -> Option<PathBuf> {
    if value.is_empty() || value.contains('\0') {
        return None;
    }
    let root = checkout.canonical_path();
    #[cfg(windows)]
    let root = dunce::simplified(root);
    let candidate = Path::new(value);
    let source = if candidate.is_absolute() {
        #[cfg(windows)]
        let candidate = dunce::simplified(candidate);
        candidate.to_path_buf()
    } else {
        if candidate.has_root()
            || matches!(candidate.components().next(), Some(Component::Prefix(_)))
        {
            return None;
        }
        root.join(candidate)
    };
    let mut resolved = PathBuf::new();
    for component in source.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                resolved.pop();
            }
            component => resolved.push(component.as_os_str()),
        }
    }
    let relative = resolved.strip_prefix(root).ok()?;
    (!relative.as_os_str().is_empty()).then(|| relative.to_path_buf())
}

fn quoted(prefix: &str, path: &str) -> String {
    let mut result = format!("\"{prefix}");
    for char in path.chars() {
        match char {
            '\\' => result.push_str("\\\\"),
            '"' => result.push_str("\\\""),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            _ => result.push(char),
        }
    }
    result.push('"');
    result
}

#[cfg(test)]
mod tests;
