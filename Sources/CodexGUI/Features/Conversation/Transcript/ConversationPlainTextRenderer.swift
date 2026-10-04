import Foundation

/// Keeps semantic Markdown block separation readable in native plain-text turn previews.
enum ConversationPlainTextRenderer
{
	static func render(_ content: ParsedConversationContent) -> String
	{
		var boundaries = content.plainTextBoundaries.makeIterator()
		var nextBoundary = boundaries.next()
		var result = ""
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
					result += String(
						repeating: "\n",
						count: max(
							0,
							boundary.newlineCount - trailingNewlines
						)
					)
				}
				nextBoundary = boundaries.next()
			}
			guard !run.style.codeHeader && !run.style.fileLinkIcon && !run.style.codePadding
			else
			{
				continue
			}
			let source = run.style.richBlock?.source ?? (run.style.thematicBreak ? "---" : nil)
			result += source.map
			{
				run.text.replacingOccurrences(
					of: "\u{FFFC}",
					with: $0
				)
			} ?? run.text
		}
		return result
	}
}
