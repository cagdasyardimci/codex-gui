use std::path::Path;

use codex_gui_core::{
    checkout::CheckoutIdentity,
    ipc::{MarkdownFileProperty, MarkdownFileView, MarkdownKind, MarkdownNode},
};

pub(super) fn render(source: &str, checkout: &CheckoutIdentity, base: &Path) -> MarkdownFileView {
    let (body, properties) = front_matter(source).unwrap_or_else(|| (source, Vec::new()));
    let mut nodes = crate::transcript_ipc::render_markdown_in(body, checkout, base);
    if let Some(nodes) = &mut nodes {
        limit_images(nodes, &mut 8);
    }
    MarkdownFileView { nodes, properties }
}

fn limit_images(nodes: &mut [MarkdownNode], remaining: &mut usize) {
    for node in nodes {
        if node.kind == MarkdownKind::Image && node.value.is_some() {
            if *remaining == 0 {
                node.value = None;
            } else {
                *remaining -= 1;
            }
        }
        limit_images(&mut node.children, remaining);
    }
}

pub(super) fn declares(nodes: &[MarkdownNode], kind: MarkdownKind, target: &str) -> bool {
    nodes.iter().any(|node| {
        (node.kind == kind && node.value.as_deref() == Some(target))
            || declares(&node.children, kind, target)
    })
}

fn front_matter(source: &str) -> Option<(&str, Vec<MarkdownFileProperty>)> {
    let mut lines = source.split_inclusive('\n');
    let first = lines.next()?;
    if first
        .trim_end_matches(['\r', '\n'])
        .trim_start_matches('\u{feff}')
        != "---"
    {
        return None;
    }
    let mut consumed = first.len();
    let mut entries: Vec<MarkdownFileProperty> = Vec::new();
    let mut accepts_items = false;
    for line in lines {
        consumed += line.len();
        if consumed > 65536 {
            return None;
        }
        let line = line.trim_end_matches(['\r', '\n']);
        if line.chars().any(char::is_control) {
            return None;
        }
        if matches!(line, "---" | "...") {
            return (!entries.is_empty()).then_some((&source[consumed..], entries));
        }
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(item) = trimmed.strip_prefix("- ")
            && line.starts_with(' ')
            && accepts_items
        {
            entries.last_mut()?.values.push(scalar(item)?);
            continue;
        }
        let (key, value) = line.split_once(':')?;
        if entries.len() >= 128
            || entries.iter().any(|entry| entry.key == key)
            || !valid_key(key)
            || (!value.is_empty() && !value.starts_with(' '))
        {
            return None;
        }
        let value = value.trim();
        accepts_items = value.is_empty() || value.starts_with('#');
        let values = if accepts_items {
            Vec::new()
        } else if let Some(inline) = value
            .strip_prefix('[')
            .and_then(|value| value.strip_suffix(']'))
        {
            inline.split(',').map(scalar).collect::<Option<Vec<_>>>()?
        } else {
            vec![scalar(value)?]
        };
        entries.push(MarkdownFileProperty {
            key: key.into(),
            values,
        });
    }
    None
}

fn valid_key(key: &str) -> bool {
    let mut bytes = key.bytes();
    bytes
        .next()
        .is_some_and(|byte| byte.is_ascii_alphabetic() || byte == b'_')
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

fn scalar(input: &str) -> Option<String> {
    let input = input.trim();
    if let Some(first) = input.chars().next()
        && matches!(first, '"' | '\'')
    {
        let inner = input.strip_prefix(first)?.strip_suffix(first)?;
        return (!inner.contains(first) && !inner.contains('\\')).then(|| inner.to_owned());
    }
    let value = input
        .split_once(" #")
        .map_or(input, |(value, _)| value.trim_end());
    (!value.is_empty() && !value.starts_with(['>', '|', '&', '*', '{', '[', '!']))
        .then(|| value.to_owned())
}
