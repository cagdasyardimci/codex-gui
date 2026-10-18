import Foundation

/// Sendable presentation values; the Markdown tree never crosses into AppKit rendering.
struct ParsedMarkdownContent: Sendable
{
	let runs: [MarkdownTextRun]
	let codeBlocks: [String]
	let codeBlockRanges: [NSRange]
	let plainTextBoundaries: [MarkdownPlainTextBoundary]
}

/// Plain-text consumers express semantic block spacing with line feeds instead of AppKit spacing.
struct MarkdownPlainTextBoundary: Sendable
{
	let runIndex: Int
	let newlineCount: Int
}

struct MarkdownTextRun: Sendable
{
	let text: String
	let style: MarkdownTextStyle
}

struct MarkdownTextStyle: Sendable
{
	var heading = 0
	var bold = false
	var italic = false
	var code = false
	var codePadding = false
	var codeBlock = false
	var codeBlockEnd = false
	var codeBlockID: Int?
	var codeLanguage: String?
	var codeHeader = false
	var thematicBreak = false
	var richBlock: MarkdownRichBlock?
	var monospaced = false
	var strikethrough = false
	var link: String?
	var listDepth = 0
	var listContinuation = false
	var listEnd = false
	var fileLinkIcon = false
	var webLinkIcon = false
	var paragraphContinuation = false
	var suppressParagraphSpacing = false
	var followedByList = false
	var quoteDepth = 0
	var quoteRailOffsets: [Int] = []
	var tableCell: MarkdownTableCell?
}

struct MarkdownTableCell: Sendable
{
	enum Alignment: Sendable
	{
		case left, center, right
	}

	struct Identity: Hashable, Sendable
	{
		let tableID: Int
		let row: Int
		let column: Int
	}

	var identity: Identity
	{
		Identity(
			tableID: tableID,
			row: row,
			column: column
		)
	}

	let tableID: Int
	let row: Int
	let column: Int
	let columnCount: Int
	let columnSpan: Int
	let rowSpan: Int
	let alignment: Alignment
	let header: Bool
}

/// A whole native attachment retains its exact source for copying and accessible text.
struct MarkdownRichBlock: Sendable
{
	enum Kind: Sendable
	{
		case math, diagram, imageGallery
	}

	let kind: Kind
	let source: String
	let payload: String
	var imagePaths: [String] = []
}

/// Shared paragraph and decoration geometry for native measurement and drawing.
enum MarkdownMetrics
{
	static let quoteIndent = LayoutTokens.Markdown.quoteIndent
	static let listIndent = LayoutTokens.Markdown.listIndent
}
