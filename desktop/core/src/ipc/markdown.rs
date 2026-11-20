use serde::{Deserialize, Serialize};
use ts_rs::TS;

use super::TranscriptRowRequest;

#[derive(Clone, Copy, Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum MarkdownKind {
    Text,
    Paragraph,
    Heading1,
    Heading2,
    Heading3,
    Heading4,
    Heading5,
    Heading6,
    Quote,
    OrderedList,
    BulletList,
    ListItem,
    Emphasis,
    Strong,
    Strike,
    Code,
    CodeBlock,
    InlineMath,
    DisplayMath,
    Table,
    TableHead,
    TableRow,
    TableCell,
    Link,
    Image,
    Break,
    Rule,
    Checkbox,
    Literal,
}

#[derive(Debug, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct MarkdownNode {
    pub kind: MarkdownKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub value: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    #[ts(type = "MarkdownNode[] | undefined")]
    pub children: Vec<MarkdownNode>,
}

#[derive(Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MarkdownTargetRequest {
    pub row: TranscriptRowRequest,
    pub target: String,
}
