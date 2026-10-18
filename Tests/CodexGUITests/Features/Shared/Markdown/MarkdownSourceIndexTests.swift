import Markdown
import Testing

@testable import CodexGUI

struct MarkdownSourceIndexTests
{
	@Test(arguments: ["", "😀é\r\nα\n", "👨‍👩‍👧‍👦\n\nβ\rγ"])
	func byteColumnRangesPreserveExactDecodingIncludingSplitScalars(_ source: String)
	{
		let index = MarkdownSourceIndex(source)
		let bytes = Array(source.utf8)
		var line = 1
		var column = 1
		var locations = [location(
			line: line,
			column: column
		)]
		for byte in bytes
		{
			if byte == 10
			{
				line += 1
				column = 1
			}
			else
			{
				column += 1
			}
			locations.append(location(
				line: line,
				column: column
			))
		}
		for lower in locations.indices
		{
			for upper in lower ..< locations.count
			{
				let expected = String(
					decoding: bytes[lower ..< upper],
					as: UTF8.self
				)
				let result = index.text(in: locations[lower] ..< locations[upper])
				#expect(result?.utf8.elementsEqual(expected.utf8) == true)
			}
		}
	}

	@Test func sourceOwningMarkupKeepsRangesAfterTabsUnicodeAndContainerPrefixes() throws
	{
		for source in [
			"👨‍👩‍👧‍👦 é before ![café](/tmp/image.png) after",
			"before\t![😀](/tmp/image.png) after",
			"😀\t![é](/tmp/image.png) after",
			"😀 é\r\n\r\n![日本語](/tmp/café.png)\r\n\r\n$$\nα\n$$",
			"> ![first](/tmp/first.png)\n> ![second](/tmp/second.png)",
			"- request\n\n  $$\n  α + β\n  $$",
			"```mermaid\n\tA[😀] --> B[é]\n```",
			"\tindented 😀\n\tmore é\n",
		]
		{
			let index = MarkdownSourceIndex(source)
			let bytes = Array(source.utf8)
			let starts = [0] + bytes.indices.filter
			{
				bytes[$0] == 10
			}.map
			{
				$0 + 1
			}
			let document = Document(
				parsing: source,
				options: [.disableSmartOpts]
			)
			func check(_ markup: any Markup) throws
			{
				if markup is Paragraph || markup is Image || markup is CodeBlock
				{
					let range = try #require(markup.range)
					let lower = starts[range.lowerBound.line - 1] + range.lowerBound.column - 1
					let upper = starts[range.upperBound.line - 1] + range.upperBound.column - 1
					let expected = String(
						decoding: bytes[lower ..< upper],
						as: UTF8.self
					)
					#expect(index.text(in: range)?.utf8.elementsEqual(expected.utf8) == true)
				}
				for child in markup.children
				{
					try check(child)
				}
			}
			try check(document)
		}
	}

	@Test func missingAndOutOfBoundsLocationsHaveNoSource()
	{
		let index = MarkdownSourceIndex("text")
		#expect(index.text(in: nil) == nil)
		for (line, column) in [(0, 1), (1, 0), (1, 10), (2, 1)]
		{
			let start = location(
				line: line,
				column: column
			)
			let end = location(
				line: line,
				column: column + 1
			)
			#expect(index.text(in: start ..< end) == nil)
		}
	}

	private func location(
		line: Int,
		column: Int
	) -> Markdown.SourceLocation
	{
		Markdown.SourceLocation(
			line: line,
			column: column,
			source: nil
		)
	}
}
