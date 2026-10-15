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

	@Test(
		arguments: ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"],
		[false, true]
	)
	func noninitialSelectionUsesLogicalSourceLines(
		separator: String,
		terminated: Bool
	) throws
	{
		let contents = "🧭 first" + separator + "second" + separator + "third"
			+ (terminated ? separator : "")
		let range = (contents as NSString).range(of: "cond" + separator + "thi")
		let selected = try #require(CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: range
		))
		#expect(selected.firstLine == 2)
		#expect(selected.lastLine == 3)
		#expect(selected.excerpt == "second" + separator + "third")
		let inputs = try ComposerContextBuilder.inputs(
			text: "Inspect",
			items: [selected],
			project: URL(fileURLWithPath: "/tmp/selection-fixture")
		)
		#expect(inputs == [.text(
			"Inspect\n\nSelected code from Example.swift, lines 2–3:\n2: second\n3: third"
		)])
	}

	@Test(arguments: ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"])
	func noninitialBlankLinesRetainExactSourceAndOutgoingNumbers(separator: String) throws
	{
		let prefix = "🧭 prefix" + separator
		let selectedText = separator + "value" + separator + separator
		let contents = prefix + selectedText + "suffix"
		let selected = try #require(CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: NSRange(
				location: (prefix as NSString).length,
				length: (selectedText as NSString).length
			)
		))
		#expect(selected.firstLine == 2)
		#expect(selected.lastLine == 4)
		#expect(selected.excerpt == separator + "value" + separator)
		let inputs = try ComposerContextBuilder.inputs(
			text: "Inspect",
			items: [selected],
			project: URL(fileURLWithPath: "/tmp/selection-fixture")
		)
		#expect(inputs == [.text(
			"Inspect\n\nSelected code from Example.swift, lines 2–4:\n2: \n3: value\n4: "
		)])
	}

	@Test(arguments: [
		("\nvalue\n", "\nvalue", 2, "1: \n2: value"),
		("\nvalue\n\n", "\nvalue\n", 3, "1: \n2: value\n3: "),
		("first\n\nlast", "first\n\nlast", 3, "1: first\n2: \n3: last"),
	])
	func blankSelectedLinesKeepTheirOutgoingSourceNumbers(
		contents: String,
		expectedExcerpt: String,
		expectedLastLine: Int,
		expectedNumberedLines: String
	) throws
	{
		let selected = try #require(CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: NSRange(
				location: 0,
				length: (contents as NSString).length
			)
		))
		#expect(selected.firstLine == 1)
		#expect(selected.lastLine == expectedLastLine)
		#expect(selected.excerpt == expectedExcerpt)
		let inputs = try ComposerContextBuilder.inputs(
			text: "Inspect",
			items: [selected],
			project: URL(fileURLWithPath: "/tmp/selection-fixture")
		)
		#expect(inputs == [.text(
			"Inspect\n\nSelected code from Example.swift, lines 1–\(expectedLastLine):\n"
				+ expectedNumberedLines
		)])
	}

	@Test(arguments: ["\n", "\n\n"])
	func entirelyBlankSelectionsRemainUnavailable(_ contents: String)
	{
		#expect(CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: NSRange(
				location: 0,
				length: (contents as NSString).length
			)
		) == nil)
	}

}
