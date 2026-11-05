import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct TerminalOutputRendererTests
{
	@Test func splitControlSequencesRetainEmphasisAndNeverBecomeVisibleText() throws
	{
		var renderer = TerminalOutputRenderer()
		let text = NSMutableAttributedString(string: "")
		for part in [
			"ordinary \u{1b}[",
			"1mstrong 日本語 👩🏽‍💻",
			"\u{1b}[0",
			"m plain\u{1b}]0;private title\u{7} tail"
		]
		{
			text.append(renderer.append(
				part,
				configuration: TypographyConfiguration(uiSize: 16)
			))
		}
		#expect(text.string == "ordinary strong 日本語 👩🏽‍💻 plain tail")
		let strong = (text.string as NSString).range(of: "strong")
		let normalFont = try #require(text.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)
		let boldFont = try #require(text.attribute(
			.font,
			at: strong.location,
			effectiveRange: nil
		) as? NSFont)
		let reset = (text.string as NSString).range(of: " plain")
		let resetFont = try #require(text.attribute(
			.font,
			at: reset.location,
			effectiveRange: nil
		) as? NSFont)
		#expect(normalFont.fontName == "Menlo-Regular")
		#expect(boldFont.fontName == "Menlo-Bold")
		#expect(resetFont == normalFont)
		#expect(normalFont.pointSize == 15)
		#expect(boldFont.pointSize == 15)
		#expect((text.attribute(
			.paragraphStyle,
			at: strong.location,
			effectiveRange: nil
		) as? NSParagraphStyle)?.minimumLineHeight == 22.5)
		#expect(text.attribute(
			.link,
			at: text.length - 1,
			effectiveRange: nil
		) == nil)
	}
}
