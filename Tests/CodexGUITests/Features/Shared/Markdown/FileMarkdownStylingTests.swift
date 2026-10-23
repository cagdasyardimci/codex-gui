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

	@Test func adjacentMatchingBlocksKeepEverySourceBlankLineGap() throws
	{
		let sources = [
			"## First\n\n## Second\n\n## Third",
			"First\n\nSecond\n\nThird",
			"First\n------\n\n## Second\n\nThird\n------",
		]
		for source in sources
		{
			let file = styled(source)
			var blockLines: Set<Int> = []
			for (label, gap) in [("First", 0.0), ("Second", 23.6), ("Third", 23.6)]
			{
				let range = (file.string as NSString).range(of: label)
				let paragraph = try #require(file.attribute(
					.paragraphStyle,
					at: range.location,
					effectiveRange: nil
				) as? NSParagraphStyle)
				#expect(abs(paragraph.paragraphSpacingBefore - gap) < 0.01)
				let line = try #require(file.attribute(
					.markdownBlockStartLine,
					at: range.location,
					effectiveRange: nil
				) as? Int)
				#expect(blockLines.insert(line).inserted)
			}
			#expect(file.string == "First\nSecond\nThird")
			#expect(MarkdownPlainTextRenderer.render(MarkdownContentParser.parse(
				source,
				markdown: true
			)) == "First\n\nSecond\n\nThird")
		}
	}

	@Test func listsAndQuotedParagraphsKeepSourceGapsAndSemanticMarkers() throws
	{
		let source = "## Heading\n\n1. First\n\n   Continuation\n\n1. Second\n\n"
			+ "> Quote\n>\n> Another\n> soft continuation"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true,
			preserveSoftBreaks: true
		)
		let shared = MarkdownAttributedStringRenderer.render(parsed.runs)
		let file = FileMarkdownStyling.apply(to: shared)
		for label in ["First", "Continuation", "Second", "Quote", "Another"]
		{
			let range = (file.string as NSString).range(of: label)
			let paragraph = try #require(file.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(abs(paragraph.paragraphSpacingBefore - 23.6) < 0.01)
		}
		#expect(file.string.contains("2. Second"))
		#expect(file.string == shared.string)
		let second = (shared.string as NSString).range(of: "Second")
		#expect((shared.attribute(
			.paragraphStyle,
			at: second.location,
			effectiveRange: nil
		) as? NSParagraphStyle)?.paragraphSpacingBefore == 0)
	}

	@Test func paragraphsEndingInInlineCodeKeepSeparatorsAndCopy() throws
	{
		let source = "First `one`\n\nSecond `two`\n\n## Heading"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let shared = MarkdownAttributedStringRenderer.render(parsed.runs)
		let file = FileMarkdownStyling.apply(to: shared)
		#expect(file.string == "First one\nSecond two\nHeading")
		#expect(MarkdownPlainTextRenderer.render(parsed) == "First one\n\nSecond two\n\nHeading")
		for index in 0 ..< file.length
			where (file.string as NSString).character(at: index) == 10
		{
			#expect(file
				.attribute(
					.markdownInlineCodeSource,
					at: index,
					effectiveRange: nil
				) == nil)
			#expect(file.attribute(
				.markdownSourceText,
				at: index,
				effectiveRange: nil
			) == nil)
		}
	}

	@Test func filesQuoteRailsJoinSoftLinesAndExcludeLeadingParagraphGaps() throws
	{
		let parsed = MarkdownContentParser.parse(
			"Before\n\n> First\n> continuation\n>\n> Second",
			markdown: true,
			preserveSoftBreaks: true
		)
		let file = FileMarkdownStyling
			.apply(to: MarkdownAttributedStringRenderer.render(parsed.runs))
		let storage = NSTextStorage(attributedString: file)
		let layout = MarkdownLayoutManager()
		let container = NSTextContainer(containerSize: NSSize(
			width: 600,
			height: 1000
		))
		layout.addTextContainer(container)
		storage.addLayoutManager(layout)
		layout.ensureLayout(for: container)
		let ranges = try #require(layout.quoteRailRanges(in: storage)[0])
		try #require(ranges.count == 2)
		#expect((storage.string as NSString).substring(with: ranges[0]) == "First\ncontinuation\n")
		for range in ranges
		{
			let rail = try #require(layout.quoteRailRect(
				forCharacterRange: range,
				in: container
			))
			let glyph = layout.glyphIndexForCharacter(at: range.location)
			let ink = layout.lineFragmentUsedRect(
				forGlyphAt: glyph,
				effectiveRange: nil
			)
			#expect(abs(rail.minY - ink.minY) < 0.01)
			#expect(rail.minY > layout.lineFragmentRect(
				forGlyphAt: glyph,
				effectiveRange: nil
			)
			.minY)
		}
	}

	@Test func fileCodeStylingPreservesListsLinksAndAlignedTableCells() throws
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
		#expect(file.string == original.string.replacingOccurrences(
			of: "\u{FFFC}",
			with: ""
		))
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
			let originalRange = (original.string as NSString).range(of: cell + "\n")
			let before = original.attribute(
				.paragraphStyle,
				at: originalRange.location,
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
				== AppKitColorTokens.primaryText)
			#expect((file.attribute(
				.font,
				at: index,
				effectiveRange: nil
			) as? NSFont)?
				.pointSize == 12)
		}
		let originalCode = (original.string as NSString).range(of: "let value = 42")
		#expect((original.attribute(
			.font,
			at: originalCode.location,
			effectiveRange: nil
		) as? NSFont)?.pointSize == 13)
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
		#expect(font.pointSize == 14)
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

	@Test func linksHaveNoIconsOrTrailingUnderlineAndEmailsExcludeCode() throws
	{
		let file = styled("[A `code` link](https://example.com)\n\nhello@example.com\n\n"
			+ "`code@example.com`\n\n```text\nblock@example.com\n```")
		#expect(!file.string.contains("\u{FFFC}"))
		let text = file.string as NSString
		let label = text.range(of: "link")
		#expect(file.attribute(
			.link,
			at: label.location,
			effectiveRange: nil
		) != nil)
		let newline = text.range(of: "\n")
		#expect(file.attribute(
			.link,
			at: newline.location,
			effectiveRange: nil
		) == nil)
		for (email, linked) in [("hello@example.com", true),
								("code@example.com", false),
								("block@example.com", false)]
		{
			let range = text.range(of: email)
			#expect((file.attribute(
				.link,
				at: range.location,
				effectiveRange: nil
			) != nil) ==
				linked)
		}
		let view = MarkdownTextView()
		view.installContent(file)
		view.setSelectedRange(NSRange(
			location: 0,
			length: file.length
		))
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		#expect(view.writeSelection(
			to: pasteboard,
			type: .string
		))
		#expect(pasteboard.string(forType: .string)?.contains("A code link") == true)
	}

	@Test func rawHTMLDoesNotRepeatItsLeadingGapOnEverySourceLine() throws
	{
		let file = styled("Before\n\n<table>\n<tr>\n<td>Value</td>\n</tr>\n</table>")
		for (label, gap) in [("<table>", 23.6), ("<tr>", 0.0), ("<td>", 0.0)]
		{
			let range = (file.string as NSString).range(of: label)
			let paragraph = try #require(file.attribute(
				.paragraphStyle,
				at: range.location,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(abs(paragraph.paragraphSpacingBefore - gap) < 0.01)
		}
	}

	@Test func codeFencesReserveTheirSourceLinesAndIndentedCodeHasNoFenceHeader() throws
	{
		for (source, fenced) in [("Before\n\n```swift\nlet value = 1\n```", true),
									("Before\n\n    let value = 1", false)]
		{
			let file = styled(source)
			let code = (file.string as NSString).range(of: "let value = 1")
			let header = code.location - 1
			#expect(file
				.attribute(
					.markdownCodeFenced,
					at: header,
					effectiveRange: nil
				) as? Bool == fenced)
			let paragraph = try #require(file.attribute(
				.paragraphStyle,
				at: header,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(paragraph.minimumLineHeight == (fenced ? 20.8 : 1))
			#expect(abs(paragraph.paragraphSpacingBefore - (fenced ? 0 : 23.6)) < 0.01)
		}
	}

	@Test func fencedLanguageHeaderKeepsBlankLineSeparationOutsideItsGlyphFragment() throws
	{
		let file = styled("Before\n\n```json\n{\n  \"enabled\": true\n}\n```")
		let code = (file.string as NSString).range(of: "{")
		try #require(code.location != NSNotFound)
		let headerIndex = code.location - 1
		let beforeStyle = try #require(file.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		let adjacent = styled("Before\n```json\n{\n  \"enabled\": true\n}\n```")
		let adjacentBeforeStyle = try #require(adjacent.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		#expect(abs(beforeStyle.paragraphSpacing - adjacentBeforeStyle.paragraphSpacing - 23.6) <
			0.01)
		let storage = NSTextStorage(attributedString: file)
		let layout = MarkdownLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: 800,
			height: 2000
		))
		storage.addLayoutManager(layout)
		layout.addTextContainer(container)
		layout.ensureLayout(for: container)
		let header = layout.lineFragmentRect(
			forGlyphAt: layout.glyphIndexForCharacter(at: headerIndex),
			effectiveRange: nil
		)
		let firstCodeLine = layout.lineFragmentRect(
			forGlyphAt: layout.glyphIndexForCharacter(at: code.location),
			effectiveRange: nil
		)
		#expect(abs(firstCodeLine.minY - header.minY - 20.8) < 0.01)
		#expect(file.string.contains("{\n  \"enabled\": true\n}"))
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
