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
			in: text,
			contents: contents,
			selectedRange: selectedRange
		)
		let selectedLines = text.substring(with: sourceLines.range)
		let excerpt = selectedLines.trimmingCharacters(in: .newlines)
		guard !excerpt.isEmpty, excerpt.utf8.count <= maximumExcerptBytes
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
		in text: NSString,
		contents: String,
		selectedRange: NSRange
	) -> SelectedSourceLines
	{
		let firstSelectedLineRange = text.lineRange(for: NSRange(
			location: selectedRange.location,
			length: 0
		))
		let excerptStart = firstSelectedLineRange.location
		let lastSelectedLocation = max(
			selectedRange.location,
			NSMaxRange(selectedRange) - 1
		)
		let lastSelectedLineRange = text.lineRange(for: NSRange(
			location: lastSelectedLocation,
			length: 0
		))
		let excerptEnd = NSMaxRange(lastSelectedLineRange)

		let textBeforeExcerpt = text.substring(to: excerptStart)
		let firstLine = textBeforeExcerpt.filter
		{
			$0 == "\n"
		}.count + 1
		let textThroughExcerpt = text.substring(to: excerptEnd)
		let precedingNewlineCount = textThroughExcerpt.filter
		{
			$0 == "\n"
		}.count
		// A final line without a newline still counts as a line in the selection.
		let includesUnterminatedFinalLine =
			excerptEnd == text.length && !contents.hasSuffix("\n")
		let lastLine = precedingNewlineCount + (includesUnterminatedFinalLine ? 1 : 0)

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
