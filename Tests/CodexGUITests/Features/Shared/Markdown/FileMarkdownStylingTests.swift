import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct FileMarkdownStylingTests
{
	@Test func fileHeadingsUseReferenceWeightAndSourceBlankLineSpacing() throws
	{
		let rendered = styled("# First\n## Second\n\n#### Fourth\n##### Fifth")
		for (text, size, spacing) in [
			("First", 24.0, 0.0),
			("Second", 20.0, 0.0),
			("Fourth", 14.0, 23.6),
			("Fifth", 14.0, 0.0),
		]
		{
			let range = (rendered.string as NSString).range(of: text)
			let font = try #require(rendered.attribute(
				.font,
				at: range.location,
				effectiveRange: nil
			) as? NSFont)
			#expect(abs(font.pointSize - size) < 0.001)
			let variation = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
			#expect(variation?[NSNumber(value: 0x77676874)]?.doubleValue == 500)
			let paragraph = try #require(rendered.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(abs(paragraph.paragraphSpacingBefore - spacing) < 0.01)
		}
	}

	@Test func stylingRetainsHighlightedCodeListsLinksAndAlignedTableCells() throws
	{
		let source = "1. Item\n1. Next\n\n[Reference][site]\n\n"
			+ "| Left | Center | Right |\n| :--- | :---: | ---: |\n| a | b | c |\n\n"
			+ "```swift\nlet value = 42\n```\n\n[site]: https://example.com"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let original = MarkdownAttributedStringRenderer.render(parsed.runs)
		let file = FileMarkdownStyling.apply(to: original)
		#expect(file.string == original.string)
		#expect(file.string.contains("2. Next"))
		let reference = (file.string as NSString).range(of: "Reference")
		#expect(file.attribute(
			.link,
			at: reference.location,
			effectiveRange: nil
		) as? URL == URL(string: "https://example.com"))
		for cell in ["a", "b", "c"]
		{
			let range = (file.string as NSString).range(of: cell + "\n")
			let before = original.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle
			let after = file.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle
			#expect(after?.alignment == before?.alignment)
			#expect(after?.textBlocks.count == 1)
		}
		let code = (file.string as NSString).range(of: "let value = 42")
		for index in code.location ..< NSMaxRange(code)
		{
			#expect(file.attribute(
				.foregroundColor,
				at: index,
				effectiveRange: nil
			) as? NSColor
				== original.attribute(
					.foregroundColor,
					at: index,
					effectiveRange: nil
				) as? NSColor)
			#expect(file.attribute(
				.font,
				at: index,
				effectiveRange: nil
			) as? NSFont
				== original.attribute(
					.font,
					at: index,
					effectiveRange: nil
				) as? NSFont)
		}
	}

	@Test func inlineCodeRetainsSourceAndFontWithoutBackgroundDecoration() throws
	{
		let file = styled("Use `a b` here.")
		let range = (file.string as NSString).range(of: "a\u{00A0}b")
		try #require(range.location != NSNotFound)
		#expect(file.attribute(
			.markdownInlineCode,
			at: range.location,
			effectiveRange: nil
		) == nil)
		#expect(file.attribute(
			.markdownInlineCodeSource,
			at: range.location,
			effectiveRange: nil
		) as? String == "a b")
		let font = try #require(file.attribute(
			.font,
			at: range.location,
			effectiveRange: nil
		) as? NSFont)
		#expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
	}

	@Test func softLineContinuationsDoNotRepeatParagraphBlankLineSpacing() throws
	{
		let parsed = MarkdownContentParser.parse(
			"First\n\nSecond\nThird",
			markdown: true,
			preserveSoftBreaks: true
		)
		let file = FileMarkdownStyling
			.apply(to: MarkdownAttributedStringRenderer.render(parsed.runs))
		for (text, expected) in [("Second", 23.6), ("Third", 0.0)]
		{
			let range = (file.string as NSString).range(of: text)
			let paragraph = try #require(file.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(abs(paragraph.paragraphSpacingBefore - expected) < 0.01)
		}
	}

	@Test func fileFormulaSizingKeepsSourceAndLeavesSharedMathUnchanged() throws
	{
		_ = NSApplication.shared
		let source = "Inline \\(E=mc^2\\)\n\n$$\nE=mc^2\n$$"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let shared = MarkdownAttributedStringRenderer.render(parsed.runs)
		let file = MarkdownAttributedStringRenderer.render(
			parsed.runs,
			mathFontSize: FileMarkdownStyling.mathFontSize
		)
		func sizes(_ text: NSAttributedString) -> [NSSize]
		{
			var result: [NSSize] = []
			text.enumerateAttribute(
				.attachment,
				in: NSRange(
					location: 0,
					length: text.length
				)
			)
			{
				value, _, _ in
				if let attachment = value as? NSTextAttachment,
					let size = attachment.attachmentCell?.cellSize()
				{
					result.append(size)
				}
			}
			return result
		}
		let sharedSizes = sizes(shared)
		let fileSizes = sizes(file)
		try #require(sharedSizes.count == 2 && fileSizes.count == 2)
		#expect(fileSizes[0].width > sharedSizes[0].width)
		#expect(fileSizes[1].width < sharedSizes[1].width)
		#expect(file.string == shared.string)
		#expect(MarkdownPlainTextRenderer.render(parsed) == source)
	}

	private func styled(_ source: String) -> NSAttributedString
	{
		FileMarkdownStyling.apply(to: MarkdownAttributedStringRenderer.render(
			MarkdownContentParser.parse(
				source,
				markdown: true
			).runs
		))
	}
}
