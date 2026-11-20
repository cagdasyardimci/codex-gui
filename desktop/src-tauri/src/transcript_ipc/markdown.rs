use codex_gui_core::{
    checkout::CheckoutIdentity,
    ipc::{MarkdownKind as Kind, MarkdownNode as Node},
};
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag};
use tauri::Url;

use super::{MAX_SOURCE_BYTES, markdown_path, relative_image};

const MAX_NODES: usize = 8192;
const MAX_DEPTH: usize = 32;
const MAX_TARGET_BYTES: usize = 4096;

pub(super) fn events(source: &str) -> Parser<'_> {
    Parser::new_ext(
        source,
        Options::ENABLE_TABLES
            | Options::ENABLE_STRIKETHROUGH
            | Options::ENABLE_TASKLISTS
            | Options::ENABLE_MATH,
    )
}

pub(crate) fn document(source: &str, checkout: &CheckoutIdentity) -> Option<Vec<Node>> {
    if source.len() > MAX_SOURCE_BYTES {
        return None;
    }
    let mut output = Vec::new();
    let mut stack: Vec<Node> = Vec::new();
    for (index, (event, range)) in events(source).into_offset_iter().enumerate() {
        if index >= MAX_NODES || stack.len() > MAX_DEPTH {
            return None;
        }
        let node = match event {
            Event::Start(tag) => {
                stack.push(container(tag, checkout)?);
                continue;
            }
            Event::End(_) => stack.pop()?,
            Event::Text(text) | Event::Html(text) | Event::InlineHtml(text) => {
                leaf(Kind::Text, Some(text.into_string()))
            }
            Event::Code(text) => leaf(Kind::Code, Some(text.into_string())),
            Event::InlineMath(text) => math(Kind::InlineMath, text.into_string(), &source[range]),
            Event::DisplayMath(text) => math(Kind::DisplayMath, text.into_string(), &source[range]),
            Event::SoftBreak => leaf(Kind::Text, Some("\n".into())),
            Event::HardBreak => leaf(Kind::Break, None),
            Event::Rule => leaf(Kind::Rule, None),
            Event::TaskListMarker(checked) => leaf(Kind::Checkbox, Some(checked.to_string())),
            _ => leaf(Kind::Text, Some(source[range].to_owned())),
        };
        stack
            .last_mut()
            .map_or(&mut output, |frame| &mut frame.children)
            .push(node);
    }
    stack.is_empty().then_some(output)
}

fn container(tag: Tag<'_>, checkout: &CheckoutIdentity) -> Option<Node> {
    let (kind, value) = match tag {
        Tag::Paragraph => (Kind::Paragraph, None),
        Tag::Heading { level, .. } => (heading(level), None),
        Tag::BlockQuote(_) => (Kind::Quote, None),
        Tag::CodeBlock(block) => (
            Kind::CodeBlock,
            match block {
                CodeBlockKind::Fenced(info) => info.split_whitespace().next().map(str::to_owned),
                CodeBlockKind::Indented => None,
            },
        ),
        Tag::HtmlBlock => (Kind::Literal, None),
        Tag::List(Some(number)) => (Kind::OrderedList, Some(number.to_string())),
        Tag::List(None) => (Kind::BulletList, None),
        Tag::Item => (Kind::ListItem, None),
        Tag::Emphasis => (Kind::Emphasis, None),
        Tag::Strong => (Kind::Strong, None),
        Tag::Strikethrough => (Kind::Strike, None),
        Tag::Link { dest_url, .. } => (Kind::Link, link(&dest_url)),
        Tag::Image { dest_url, .. } => (
            Kind::Image,
            (dest_url.len() <= MAX_TARGET_BYTES)
                .then(|| markdown_path(&dest_url))
                .flatten()
                .and_then(|path| relative_image(checkout, &path)),
        ),
        Tag::Table(_) => (Kind::Table, None),
        Tag::TableHead => (Kind::TableHead, None),
        Tag::TableRow => (Kind::TableRow, None),
        Tag::TableCell => (Kind::TableCell, None),
        _ => return None,
    };
    Some(leaf(kind, value))
}

fn leaf(kind: Kind, value: Option<String>) -> Node {
    Node {
        kind,
        value,
        children: Vec::new(),
    }
}

fn math(kind: Kind, formula: String, source: &str) -> Node {
    Node {
        kind,
        value: Some(formula),
        children: vec![leaf(Kind::Text, Some(source.into()))],
    }
}

fn heading(level: HeadingLevel) -> Kind {
    match level {
        HeadingLevel::H1 => Kind::Heading1,
        HeadingLevel::H2 => Kind::Heading2,
        HeadingLevel::H3 => Kind::Heading3,
        HeadingLevel::H4 => Kind::Heading4,
        HeadingLevel::H5 => Kind::Heading5,
        HeadingLevel::H6 => Kind::Heading6,
    }
}

fn link(raw: &str) -> Option<String> {
    if raw.len() > MAX_TARGET_BYTES || raw.chars().any(char::is_control) {
        return None;
    }
    if let Some(fragment) = raw.strip_prefix('#') {
        return (!fragment.is_empty()).then(|| raw.to_owned());
    }
    external_url(raw).map(Into::into)
}

pub(super) fn external_url(raw: &str) -> Option<Url> {
    let url = Url::parse(raw).ok()?;
    let web = matches!(url.scheme(), "http" | "https")
        && url.host().is_some()
        && url.username().is_empty()
        && url.password().is_none();
    let mail = url.scheme() == "mailto" && url.path().contains('@') && url.host().is_none();
    (web || mail).then_some(url)
}

pub(super) fn contains_link(nodes: &[Node], target: &str) -> bool {
    nodes.iter().any(|node| {
        (node.kind == Kind::Link && node.value.as_deref() == Some(target))
            || (node.kind != Kind::Image && contains_link(&node.children, target))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_source_as_fallback_when_rendering_limits_are_exceeded() {
        let temp = tempfile::tempdir().unwrap();
        let checkout = CheckoutIdentity::capture(temp.path()).unwrap();
        assert!(document(&"a".repeat(MAX_SOURCE_BYTES + 1), &checkout).is_none());
        assert!(document(&"*word* ".repeat(MAX_NODES), &checkout).is_none());
        assert!(document(&("> ".repeat(MAX_DEPTH + 1) + "text"), &checkout).is_none());
    }
}
