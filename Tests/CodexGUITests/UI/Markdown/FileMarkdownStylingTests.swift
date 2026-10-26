import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct FileMarkdownStylingTests
{

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
