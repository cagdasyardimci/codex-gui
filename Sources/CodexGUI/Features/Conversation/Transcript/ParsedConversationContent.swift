import Foundation

/// Sendable presentation values; the Markdown tree never crosses into AppKit rendering.
struct ParsedConversationContent: Sendable
{
	let runs: [ConversationTextRun]
	let codeBlocks: [String]
	let codeBlockRanges: [NSRange]
	let plainTextBoundaries: [ConversationPlainTextBoundary]
}

/// Plain-text consumers express semantic block spacing with line feeds instead of AppKit spacing.
struct ConversationPlainTextBoundary: Sendable
{
	let runIndex: Int
	let newlineCount: Int
}

struct ConversationTextRun: Sendable
{
	let text: String
	let style: ConversationTextStyle
}

struct ConversationTextStyle: Sendable
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
	var richBlock: ConversationRichBlock?
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
	var tableCell: ConversationTableCell?
}

struct ConversationTableCell: Sendable
{
	enum Alignment: Sendable
	{
		case left, center, right
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
struct ConversationRichBlock: Sendable
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
enum ConversationMarkdownMetrics
{
	static let quoteIndent = LayoutTokens.Markdown.quoteIndent
	static let listIndent = LayoutTokens.Markdown.listIndent
}
