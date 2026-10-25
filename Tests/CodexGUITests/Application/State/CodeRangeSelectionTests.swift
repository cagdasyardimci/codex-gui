import Foundation
import Testing

@testable import CodexGUI

@Suite
struct CodeRangeSelectionTests
{
	@Test func codeSelectionRecordsInclusiveSourceLines()
	{
		let contents = "first\nsecond\nthird\n"
		let range = (contents as NSString).range(of: "cond\nthi")
		let selected = CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: range
		)
		#expect(selected?.firstLine == 2)
		#expect(selected?.lastLine == 3)
		#expect(selected?.excerpt == "second\nthird")
		#expect(
			CodeRangeSelection.item(
				path: "Example.swift",
				contents: contents,
				selectedRange: NSRange(
					location: 0,
					length: 0
				)
			) == nil
		)
	}

}
