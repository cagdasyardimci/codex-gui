import AppKit

extension NSAttributedString.Key
{
	static let markdownSourceText = NSAttributedString.Key("conversationSourceText")
	static let markdownInlineCodeSource = NSAttributedString.Key("conversationInlineCodeSource")
	static let markdownInlineCode = NSAttributedString.Key("conversationInlineCode")
	static let markdownCodeBlockID = NSAttributedString.Key("conversationCodeBlockID")
	static let markdownCodeHeader = NSAttributedString.Key("conversationCodeHeader")
	static let markdownCodeFenced = NSAttributedString.Key("markdownCodeFenced")
	static let markdownCodeLanguage = NSAttributedString.Key("conversationCodeLanguage")
	static let markdownQuoteDepth = NSAttributedString.Key("conversationQuoteDepth")
	static let markdownQuoteRailOffsets = NSAttributedString.Key("conversationQuoteRailOffsets")
	static let markdownThematicBreak = NSAttributedString.Key("conversationThematicBreak")
	static let markdownHeadingLevel = NSAttributedString.Key("markdownHeadingLevel")
	static let markdownBlankLinesBefore = NSAttributedString.Key("markdownBlankLinesBefore")
	static let markdownBlockStartLine = NSAttributedString.Key("markdownBlockStartLine")
	static let markdownFilePreview = NSAttributedString.Key("markdownFilePreview")
	static let markdownParagraphRole = NSAttributedString.Key("markdownParagraphRole")
}
