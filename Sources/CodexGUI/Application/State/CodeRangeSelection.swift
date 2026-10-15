import Foundation

enum CodeRangeSelection
{
	private static let maximumExcerptBytes = 30_000

	static func item(
		path: String,
		contents: String,
		selectedRange: NSRange
	) -> ComposerContextItem?
	{
		let text = contents as NSString
		guard selectedRange.length > 0, selectedRange.location != NSNotFound,
				NSMaxRange(selectedRange) <= text.length
		else
		{
			return nil
		}

		let sourceLines = selectedSourceLines(
			in: SourceLineIndex(contents),
			selectedRange: selectedRange
		)
		let excerpt = text.substring(with: sourceLines.range)
		guard !excerpt.trimmingCharacters(in: .newlines).isEmpty,
				excerpt.utf8.count <= maximumExcerptBytes
		else
		{
			return nil
		}

		return ComposerContextItem(
			kind: .textExcerpt,
			title: URL(fileURLWithPath: path).lastPathComponent,
			path: path,
			firstLine: sourceLines.firstLine,
			lastLine: max(
				sourceLines.firstLine,
				sourceLines.lastLine
			),
			excerpt: excerpt
		)
	}

	private struct SelectedSourceLines
	{
		let range: NSRange
		let firstLine: Int
		let lastLine: Int
	}

	private static func selectedSourceLines(
		in index: SourceLineIndex,
		selectedRange: NSRange
	) -> SelectedSourceLines
	{
		let firstLine = index.lineNumber(atUTF16Offset: selectedRange.location)
		let lastSelectedLocation = max(
			selectedRange.location,
			NSMaxRange(selectedRange) - 1
		)
		let lastLine = index.lineNumber(atUTF16Offset: lastSelectedLocation)
		let excerptStart = index.contentRange(atLineIndex: firstLine - 1).location
		let excerptEnd = NSMaxRange(index.contentRange(atLineIndex: lastLine - 1))
		let excerptRange = NSRange(
			location: excerptStart,
			length: excerptEnd - excerptStart
		)
		return SelectedSourceLines(
			range: excerptRange,
			firstLine: firstLine,
			lastLine: lastLine
		)
	}
}
