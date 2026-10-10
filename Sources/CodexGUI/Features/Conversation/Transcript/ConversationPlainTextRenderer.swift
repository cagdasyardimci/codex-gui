import Foundation

struct ConversationPlainTextLink: Equatable, Sendable
{
	let range: NSRange
	let destination: String
}

struct ConversationPlainTextPresentation: Sendable
{
	let text: String
	let links: [ConversationPlainTextLink]
}

/// Keeps semantic Markdown block separation readable in native plain-text turn previews.
enum ConversationPlainTextRenderer
{
	static func render(_ content: ParsedConversationContent) -> String
	{
		renderWithLinks(content).text
	}

	static func renderWithLinks(_ content: ParsedConversationContent)
		-> ConversationPlainTextPresentation
	{
		var boundaries = content.plainTextBoundaries.makeIterator()
		var nextBoundary = boundaries.next()
		var result = ""
		var links: [ConversationPlainTextLink] = []
		var textLength = 0
		for (index, run) in content.runs.enumerated()
		{
			while let boundary = nextBoundary, boundary.runIndex == index
			{
				if !result.isEmpty
				{
					let trailingNewlines = result.reversed().prefix
					{
						$0 == "\n"
					}.count
					let spacer = String(
						repeating: "\n",
						count: max(
							0,
							boundary.newlineCount - trailingNewlines
						)
					)
					result += spacer
					textLength += spacer.utf16.count
				}
				nextBoundary = boundaries.next()
			}
			guard !run.style.codeHeader && !run.style.fileLinkIcon &&
				!run.style.webLinkIcon && !run.style.codePadding
			else
			{
				continue
			}
			let source = run.style.richBlock?.source ?? (run.style.thematicBreak ? "---" : nil)
			let display = source.map
			{
				run.text.replacingOccurrences(
					of: "\u{FFFC}",
					with: $0
				)
			} ?? run.text
			if let destination = run.style.link,
				WebLinkDetector.webURL(destination) != nil,
				!display.isEmpty
			{
				let range = NSRange(
					location: textLength,
					length: display.utf16.count
				)
				if let last = links.last, last.destination == destination,
					NSMaxRange(last.range) == range.location
				{
					links[links.count - 1] = ConversationPlainTextLink(
						range: NSRange(
							location: last.range.location,
							length: last.range.length + range.length
						),
						destination: destination
					)
				}
				else
				{
					links.append(ConversationPlainTextLink(
						range: range,
						destination: destination
					))
				}
			}
			result += display
			textLength += display.utf16.count
		}
		return ConversationPlainTextPresentation(
			text: result,
			links: links
		)
	}
}
