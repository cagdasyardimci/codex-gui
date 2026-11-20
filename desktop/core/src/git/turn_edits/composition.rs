use std::collections::HashMap;

use super::*;

const MAX_LINES: usize = 8_192;
const MAX_HUNKS: usize = 256;
const MAX_DIFFERENCE_CELLS: usize = 1_000_000;

pub(super) fn compose(edits: &[&ReportedEdit]) -> (Vec<TurnFileEdit>, bool) {
    let mut groups: Vec<Vec<&ReportedEdit>> = Vec::new();
    let mut paths = HashMap::new();
    let mut exact = true;
    for &edit in edits {
        let group = paths.get(&edit.path).copied().unwrap_or_else(|| {
            let index = groups.len();
            groups.push(Vec::new());
            index
        });
        groups[group].push(edit);
        if let Some(destination) = &edit.destination {
            paths.remove(&edit.path);
            if paths
                .insert(destination.clone(), group)
                .is_some_and(|other| other != group)
            {
                exact = false;
            }
        } else {
            paths.insert(edit.path.clone(), group);
        }
    }
    let mut files = Vec::new();
    for group in groups {
        match net_file(&group) {
            Some(Some(file)) => files.push(file),
            Some(None) => {}
            None => {
                exact = false;
                files.extend(group.into_iter().map(|edit| {
                    let (before, after) = endpoints(edit, edit);
                    TurnFileEdit::new(before, after, normalise(edit))
                }));
            }
        }
    }
    (files, exact)
}

fn net_file(edits: &[&ReportedEdit]) -> Option<Option<TurnFileEdit>> {
    let first = *edits.first()?;
    let last = *edits.last()?;
    let (before, after) = endpoints(first, last);
    let diff = if edits.len() == 1 {
        let original = normalise(first);
        if original.is_empty() {
            if first.kind == EditKind::Update && first.destination.is_none() {
                return None;
            }
            original
        } else {
            let hunks = parse(&original)?;
            if hunks.iter().any(|hunk| {
                (first.kind == EditKind::Add && hunk.old != (0, 0))
                    || (first.kind == EditKind::Delete && hunk.new != (0, 0))
            }) {
                return None;
            }
            render(&hunks)
        }
    } else {
        let mut material = Material::new(first.kind == EditKind::Add);
        let mut deleted = false;
        for (index, edit) in edits.iter().enumerate() {
            if index != 0 && (edit.kind == EditKind::Add) != deleted {
                return None;
            }
            material.apply(edit)?;
            deleted = edit.kind == EditKind::Delete;
            if deleted && !material.current.is_empty() {
                return None;
            }
        }
        material.diff()?
    };
    if (before.is_none() && after.is_none()) || (before == after && diff.is_empty()) {
        return Some(None);
    }
    Some(Some(TurnFileEdit::new(before, after, diff)))
}

fn endpoints(first: &ReportedEdit, last: &ReportedEdit) -> (Option<PathBuf>, Option<PathBuf>) {
    (
        (first.kind != EditKind::Add).then(|| first.path.clone()),
        (last.kind != EditKind::Delete)
            .then(|| last.destination.as_ref().unwrap_or(&last.path).clone()),
    )
}

fn normalise(edit: &ReportedEdit) -> String {
    if edit.diff.is_empty()
        || edit.kind == EditKind::Update
        || edit.diff.lines().any(|line| line.starts_with("@@ "))
    {
        return edit.diff.trim_end_matches('\n').to_owned();
    }
    let body = edit.diff.strip_suffix('\n').unwrap_or(&edit.diff);
    let lines: Vec<_> = body.split('\n').collect();
    let added = edit.kind == EditKind::Add;
    let mut text = if added {
        format!("@@ -0,0 +1,{} @@", lines.len())
    } else {
        format!("@@ -1,{} +0,0 @@", lines.len())
    };
    for line in lines {
        text.push('\n');
        text.push(if added { '+' } else { '-' });
        text.push_str(line);
    }
    if !edit.diff.ends_with('\n') {
        text.push_str("\n\\ No newline at end of file");
    }
    text
}

struct Hunk<'a> {
    header: &'a str,
    old: (usize, usize),
    new: (usize, usize),
    lines: Vec<&'a str>,
}

fn parse(patch: &str) -> Option<Vec<Hunk<'_>>> {
    let mut hunks: Vec<Hunk> = Vec::new();
    for line in patch.split_terminator('\n') {
        if line.starts_with("@@ ") {
            let mut range = line.split_whitespace().skip(1);
            let old = parse_range(range.next()?.strip_prefix('-')?)?;
            let new = parse_range(range.next()?.strip_prefix('+')?)?;
            if range.next()? != "@@" || hunks.len() == MAX_HUNKS {
                return None;
            }
            hunks.push(Hunk {
                header: line,
                old,
                new,
                lines: Vec::new(),
            });
        } else if let Some(hunk) = hunks.last_mut() {
            match line.as_bytes().first() {
                Some(b'+' | b'-' | b' ') => hunk.lines.push(line),
                Some(b'\\') if line == "\\ No newline at end of file" && !hunk.lines.is_empty() => {
                    hunk.lines.push(line);
                }
                _ => return None,
            }
        } else if !line.is_empty()
            && !["diff --git ", "index ", "--- ", "+++ "]
                .iter()
                .any(|prefix| line.starts_with(prefix))
        {
            return None;
        }
    }
    let mut old_end = 0usize;
    let mut new_end = 0usize;
    for hunk in &hunks {
        let old_start = hunk.old.0.checked_sub(usize::from(hunk.old.1 != 0))?;
        let new_start = hunk.new.0.checked_sub(usize::from(hunk.new.1 != 0))?;
        if old_start.checked_sub(old_end)? != new_start.checked_sub(new_end)? {
            return None;
        }
        let mut old = 0;
        let mut new = 0;
        for line in &hunk.lines {
            old += usize::from(matches!(line.as_bytes()[0], b'-' | b' '));
            new += usize::from(matches!(line.as_bytes()[0], b'+' | b' '));
        }
        if old != hunk.old.1 || new != hunk.new.1 {
            return None;
        }
        old_end = old_start.checked_add(old)?;
        new_end = new_start.checked_add(new)?;
    }
    (!hunks.is_empty()).then_some(hunks)
}

fn parse_range(input: &str) -> Option<(usize, usize)> {
    match input.split_once(',') {
        Some((start, count)) => {
            let start = start.parse().ok()?;
            let count = count.parse().ok()?;
            (start != 0 || count == 0).then_some((start, count))
        }
        None => {
            let start = input.parse().ok()?;
            (start != 0).then_some((start, 1))
        }
    }
}

fn render(hunks: &[Hunk<'_>]) -> String {
    hunks
        .iter()
        .flat_map(|hunk| [hunk.header].into_iter().chain(hunk.lines.iter().copied()))
        .collect::<Vec<_>>()
        .join("\n")
}

#[derive(Clone)]
struct Line {
    origin: Option<usize>,
    text: Option<String>,
}

struct Material {
    created: bool,
    original: Vec<Option<String>>,
    current: Vec<Line>,
    applications: usize,
}

impl Material {
    fn new(created: bool) -> Self {
        Self {
            created,
            original: Vec::new(),
            current: Vec::new(),
            applications: 0,
        }
    }

    fn extend(&mut self, until: usize) -> Option<()> {
        let extra = until.saturating_sub(self.current.len());
        if (self.created && extra != 0)
            || until > MAX_LINES
            || self.original.len() + extra > MAX_LINES
        {
            return None;
        }
        for _ in 0..extra {
            self.current.push(Line {
                origin: Some(self.original.len()),
                text: None,
            });
            self.original.push(None);
        }
        Some(())
    }

    fn apply(&mut self, edit: &ReportedEdit) -> Option<()> {
        let patch = normalise(edit);
        if patch.is_empty() {
            return (edit.kind != EditKind::Update || edit.destination.is_some()).then_some(());
        }
        let mut delta = 0isize;
        let mut previous_end = 0;
        for hunk in parse(&patch)? {
            self.applications += 1;
            let (old_start, old_count) = hunk.old;
            let (new_start, new_count) = hunk.new;
            let start = old_start.checked_sub(usize::from(old_count != 0))?;
            let end = start.checked_add(old_count)?;
            let current_start = start.checked_add_signed(delta)?;
            let current_end = current_start.checked_add(old_count)?;
            if self.applications > MAX_HUNKS
                || new_count > MAX_LINES
                || start < previous_end
                || current_start.checked_add(usize::from(new_count != 0))? != new_start
                || (edit.kind == EditKind::Add && current_end != 0)
            {
                return None;
            }
            self.extend(current_end)?;
            if self.current.len() - old_count + new_count > MAX_LINES {
                return None;
            }
            let mut at = current_start;
            let mut replacement = Vec::new();
            for raw in hunk.lines {
                let body = &raw[1..];
                match raw.as_bytes()[0] {
                    b'+' => replacement.push(Line {
                        origin: None,
                        text: Some(body.to_owned()),
                    }),
                    mark @ (b'-' | b' ') => {
                        let mut source = self.current.get(at)?.clone();
                        if source.text.as_deref().is_some_and(|text| text != body) {
                            return None;
                        }
                        source.text = Some(body.to_owned());
                        if let Some(origin) = source.origin {
                            self.original[origin] = source.text.clone();
                        }
                        if mark == b' ' {
                            replacement.push(source);
                        }
                        at += 1;
                    }
                    _ => return None,
                }
            }
            self.current.splice(current_start..current_end, replacement);
            previous_end = end;
            delta += new_count as isize - old_count as isize;
        }
        Some(())
    }

    fn diff(&self) -> Option<String> {
        let original: Vec<_> = self
            .original
            .iter()
            .enumerate()
            .map(|(index, text)| token(Some(index), text.as_deref()))
            .collect::<Option<_>>()?;
        let current: Vec<_> = self
            .current
            .iter()
            .map(|line| token(line.origin, line.text.as_deref()))
            .collect::<Option<_>>()?;
        let prefix = original
            .iter()
            .zip(&current)
            .take_while(|(a, b)| a == b)
            .count();
        let suffix = original[prefix..]
            .iter()
            .rev()
            .zip(current[prefix..].iter().rev())
            .take_while(|(a, b)| a == b)
            .count();
        let before = &original[prefix..original.len() - suffix];
        let after = &current[prefix..current.len() - suffix];
        build_patch(before, after, prefix)
    }
}

#[derive(Eq, PartialEq)]
enum Token<'a> {
    Text(&'a str),
    Unknown(usize),
}

fn token(origin: Option<usize>, text: Option<&str>) -> Option<Token<'_>> {
    text.map(Token::Text).or_else(|| origin.map(Token::Unknown))
}

fn build_patch(before: &[Token<'_>], after: &[Token<'_>], prefix: usize) -> Option<String> {
    let width = after.len() + 1;
    let cells = (before.len() + 1) * width;
    if cells > MAX_DIFFERENCE_CELLS {
        return None;
    }
    let mut lengths = vec![0u16; cells];
    for i in (0..before.len()).rev() {
        for j in (0..after.len()).rev() {
            let position = i * width + j;
            lengths[position] = if before[i] == after[j] {
                1 + lengths[position + width + 1]
            } else {
                lengths[position + width].max(lengths[position + 1])
            };
        }
    }
    let mut result = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < before.len() || j < after.len() {
        if i < before.len() && j < after.len() && before[i] == after[j] {
            i += 1;
            j += 1;
            continue;
        }
        let (old, new) = (i, j);
        let mut lines = Vec::new();
        while i < before.len() || j < after.len() {
            if i < before.len() && j < after.len() && before[i] == after[j] {
                break;
            }
            if i < before.len()
                && (j == after.len() || lengths[(i + 1) * width + j] >= lengths[i * width + j + 1])
            {
                let Token::Text(text) = before[i] else {
                    return None;
                };
                lines.push(format!("-{text}"));
                i += 1;
            } else {
                let Token::Text(text) = after[j] else {
                    return None;
                };
                lines.push(format!("+{text}"));
                j += 1;
            }
        }
        let old_count = i - old;
        let new_count = j - new;
        result.push(format!(
            "@@ -{},{} +{},{} @@",
            old + prefix + usize::from(old_count != 0),
            old_count,
            new + prefix + usize::from(new_count != 0),
            new_count,
        ));
        result.extend(lines);
    }
    Some(result.join("\n"))
}
