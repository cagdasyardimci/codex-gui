import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct FileMarkdownStylingTests
{
	@Test func previewUIScopePreservesInlineCodeFamilyAndIndependentFencedCode() throws
	{
		let parsed = MarkdownContentParser.parse(
			"# Heading\n\nBody **strong** `inline`\n\n```swift\nlet value = 1\n```",
			markdown: true
		)
		let original = MarkdownAttributedStringRenderer.render(parsed.runs)
		let small = FileMarkdownStyling.apply(
			to: original,
			configuration: TypographyConfiguration(
				uiSize: 16,
				contentSize: 12,
				codeSize: 10
			)
		)
		let large = FileMarkdownStyling.apply(
			to: original,
			configuration: TypographyConfiguration(
				uiSize: 11,
				contentSize: 24,
				codeSize: 10
			)
		)
		for (text, smallSize, largeSize): (String, CGFloat, CGFloat) in [
			("Heading", 27, 19),
			("Body", 16, 11),
			("strong", 16, 11),
			("inline", 16, 11),
			("let value", 10, 10)
		]
		{
			for (content, size) in [(small, smallSize), (large, largeSize)]
			{
				let range = (content.string as NSString).range(of: text)
				let font = try #require(content.attribute(
					.font,
					at: range.location,
					effectiveRange: nil
				) as? NSFont)
				#expect(font.pointSize == size)
				if text == "inline"
				{
					#expect(font.fontName.contains("Menlo"))
				}
			}
		}
		#expect(small.string == large.string)
	}

	@Test func fileReferencesDisplayAndResolveLineNumbers() throws
	{
		let parsed = MarkdownContentParser.parse(
			"[Source](/tmp/My%20Project/File.swift:22)",
			markdown: true
		)
		let rendered = MarkdownAttributedStringRenderer.render(parsed.runs)
		#expect(rendered.string.contains("Source (line 22)"))
		let label = (rendered.string as NSString).range(of: "Source")
		let transcriptInk = try #require(rendered.attribute(
			.foregroundColor,
			at: label.location,
			effectiveRange: nil
		) as? NSColor)
		#expect(transcriptInk.usingColorSpace(.sRGB) == AppKitColorTokens.inlineReferenceText
			.usingColorSpace(.sRGB))
		let file = FileMarkdownStyling.apply(to: rendered)
		let fileLabel = (file.string as NSString).range(of: "Source")
		let fileInk = try #require(file.attribute(
			.foregroundColor,
			at: fileLabel.location,
			effectiveRange: nil
		) as? NSColor)
		#expect(fileInk.usingColorSpace(.sRGB) == MarkdownAttributedStringRenderer.linkColor
			.usingColorSpace(.sRGB))
		#expect(!file.string.contains("\u{FFFC}"))
		let reference = try #require(MarkdownFileReference("/tmp/My%20Project/File.swift:22"))
		#expect(reference.path == "/tmp/My Project/File.swift")
		#expect(reference.line == 22)
		let fileURL = try #require(MarkdownFileReference("file:///tmp/File.swift#L8"))
		#expect(fileURL.path == "/tmp/File.swift")
		#expect(fileURL.line == 8)
		#expect(MarkdownFileReference("https://example.com/file:22") == nil)
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
		let inlineCode = text.range(of: "code")
		let codeInk = try #require(file.attribute(
			.foregroundColor,
			at: inlineCode.location,
			effectiveRange: nil
		) as? NSColor)
		#expect(codeInk.usingColorSpace(.sRGB) == AppKitColorTokens.primaryText
			.usingColorSpace(.sRGB))
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
