import Foundation
import Testing

@testable import CodexGUI

struct MarkdownSourcePreservationTests
{
	@Test func inlineImageSourceUsesByteColumnsAfterComposedGraphemes() throws
	{
		let source = "![café é](/tmp/image.png)"
		let parsed = MarkdownContentParser.parse(
			"👨‍👩‍👧‍👦 é before " + source + " after",
			markdown: true
		)
		let image = try #require(parsed.runs.compactMap(\.style.richBlock).first)
		#expect(image.kind == .imageGallery)
		#expect(image.source.utf8.elementsEqual(source.utf8))
		#expect(image.imagePaths == ["/tmp/image.png"])
		#expect(parsed.runs.contains
		{
			$0.text.contains("👨‍👩‍👧‍👦 é before ")
		})
		#expect(parsed.runs.last?.text == " after")
	}

	@Test func richSourcesKeepByteColumnsAfterUnicodeAndMixedLineEndings() throws
	{
		let image = "![日本語](/tmp/café.png)"
		let math = "$$\nα + β = 😀\n$$"
		let diagram = "~~~mermaid\nflowchart LR\n    A[日本語] --> B[café]\n~~~"
		let body = "😀 é\r\n\r\n" + image + "\r\n\r\n" + math + "\n\n" + diagram
		let parsed = MarkdownContentParser.parse(
			body,
			markdown: true
		)
		let blocks = parsed.runs.compactMap(\.style.richBlock)
		try #require(blocks.count == 3)
		let gallery = try #require(blocks.first)
		#expect(gallery.source.utf8.elementsEqual(image.utf8))
		#expect(gallery.imagePaths == ["/tmp/café.png"])
		#expect(blocks[1].source.utf8.elementsEqual(math.utf8))
		#expect(blocks[1].payload == "α + β = 😀")
		#expect(blocks[2].source.utf8.elementsEqual(diagram.utf8))
		#expect(blocks[2].payload == "flowchart LR\n    A[日本語] --> B[café]\n")
	}

	@Test func sourceRangesKeepNestedContainerPrefixes() throws
	{
		let first = "![first](/tmp/first.png)"
		let second = "![second](/tmp/second.png)"
		let parsed = MarkdownContentParser.parse(
			"😀 before\n\n> " + first + "\n> " + second
				+ "\n\n- request\n\n  $$\n  α + β\n  $$",
			markdown: true
		)
		let blocks = parsed.runs.compactMap(\.style.richBlock)
		try #require(blocks.count == 2)
		let gallery = try #require(blocks.first)
		#expect(gallery.source == first + "\n> " + second)
		#expect(gallery.imagePaths == ["/tmp/first.png", "/tmp/second.png"])
		#expect(blocks[1].kind == .math)
		#expect(blocks[1].source == "$$\n  α + β\n  $$")
		#expect(blocks[1].payload == "  α + β")
	}

	@Test func displayMathRetainsInteriorWhitespaceAndRequiresMatchingDelimiters() throws
	{
		let source = "$$\n  α + β  \n\tγ = 😀\n$$"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let math = try #require(parsed.runs.compactMap(\.style.richBlock).first)
		#expect(math.source == source)
		#expect(math.payload == "  α + β  \n\tγ = 😀")
		for ordinary in [
			"$$\nα\n\\]",
			"first\nsecond\nthird",
			"$$\nlast",
			"\\[\nlast",
			"$$\r\nα\r\n$$",
		]
		{
			let content = MarkdownContentParser.parse(
				ordinary,
				markdown: true
			)
			#expect(content.runs.allSatisfy
			{
				$0.style.richBlock == nil
			})
		}
	}
}
