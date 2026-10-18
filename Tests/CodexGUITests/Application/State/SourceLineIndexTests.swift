import Foundation
import Testing

@testable import CodexGUI

struct SourceLineIndexTests
{
	@Test func consecutiveSeparatorsPreserveUTF16RangesAndEmptyLines()
	{
		let text = "🧭e\u{301}\r\n\r\r\n\nline\u{2028}\u{2029}"
		let index = SourceLineIndex(text)
		#expect(index.utf16Length == 16)
		#expect(index.lineStarts == [0, 6, 7, 9, 10, 15, 16])
		#expect(index.lines == ["🧭e\u{301}", "", "", "", "line", "", ""])
		let source = text as NSString
		let expectedLengths = [4, 0, 0, 0, 4, 0, 0]
		for line in index.lineStarts.indices
		{
			let range = NSRange(
				location: index.lineStarts[line],
				length: expectedLengths[line]
			)
			#expect(index.contentRange(atLineIndex: line) == range)
			#expect(index.contentRange(
				atLineIndex: line,
				in: source
			) == range)
		}
		#expect(index.lineNumber(atUTF16Offset: 4) == 1)
		#expect(index.lineNumber(atUTF16Offset: 5) == 1)
		#expect(index.lineNumber(atUTF16Offset: 6) == 2)
		#expect(index.lineNumber(atUTF16Offset: 7) == 3)
		#expect(index.lineNumber(atUTF16Offset: 8) == 3)
		#expect(index.lineNumber(atUTF16Offset: 9) == 4)
	}

	@Test func emptyAndUnterminatedDocumentsRetainLogicalLineSemantics()
	{
		let empty = SourceLineIndex("")
		#expect(empty.lineStarts == [0])
		#expect(empty.utf16Length == 0)
		#expect(empty.lines == [""])
		let text = SourceLineIndex("🧭\u{85}e\u{301}")
		#expect(text.lineStarts == [0])
		#expect(text.utf16Length == 5)
		#expect(text.lines == ["🧭\u{85}e\u{301}"])
		#expect(text.lineNumber(atUTF16Offset: -1) == 1)
		#expect(text.lineNumber(atUTF16Offset: 100) == 1)
	}

	@Test func largeMixedUnicodeDocumentRetainsOffsetsThroughTheFinalEmptyLine()
	{
		let repetitions = 2_048
		let index = SourceLineIndex(String(
			repeating: "🧭e\u{301}\r\n\n",
			count: repetitions
		))
		#expect(index.utf16Length == repetitions * 7)
		#expect(index.lineStarts.count == repetitions * 2 + 1)
		#expect(index.lineStarts.prefix(5).elementsEqual([0, 6, 7, 13, 14]))
		#expect(index.lineStarts.suffix(3).elementsEqual([
			(repetitions - 1) * 7,
			repetitions * 7 - 1,
			repetitions * 7,
		]))
		#expect(index.lineNumber(atUTF16Offset: index.utf16Length) == repetitions * 2 + 1)
		#expect(index.lines.last == "")
	}
}
