import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct MarkdownInlineMathRenderingTests
{
	@Test func inlineMathSharesTextLineAndCopiesOriginalDelimiters() throws
	{
		_ = NSApplication.shared
		let formula = #"\(x_i + y_i\)"#
		let source = "Before " + formula + " after"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let rendered = MarkdownAttributedStringRenderer.render(parsed.runs)
		let range = (rendered.string as NSString).range(of: "\u{FFFC}")
		try #require(range.location != NSNotFound)
		let attachment = try #require(rendered.attribute(
			.attachment,
			at: range.location,
			effectiveRange: nil
		) as? MarkdownInlineMathAttachment)
		#expect(attachment.rendersNativeImage)
		#expect(attachment.source == formula)
		let paragraph = try #require(rendered.attribute(
			.paragraphStyle,
			at: range.location,
			effectiveRange: nil
		) as? NSParagraphStyle)
		#expect(paragraph.alignment == .natural)
		let cell = try #require(attachment.attachmentCell)
		#expect(cell.cellSize().width > 0 && cell.cellSize().width < 150)
		#expect(cell.cellSize().height > 0 && cell.cellSize().height < 30)
		#expect(cell.cellBaselineOffset().y < 0)
		let storage = NSTextStorage(attributedString: rendered)
		let manager = MarkdownLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: 640,
			height: 500
		))
		container.lineFragmentPadding = 0
		manager.addTextContainer(container)
		storage.addLayoutManager(manager)
		manager.ensureLayout(for: container)
		let before = manager.lineFragmentRect(
			forGlyphAt: 0,
			effectiveRange: nil
		)
		let after = manager.lineFragmentRect(
			forGlyphAt: manager.numberOfGlyphs - 1,
			effectiveRange: nil
		)
		#expect(before == after)
		#expect(before.height < 45)
		let textView = MarkdownTextView(frame: .zero)
		try #require(textView.textStorage).setAttributedString(rendered)
		textView.setSelectedRange(NSRange(
			location: 0,
			length: rendered.length
		))
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		#expect(textView.writeSelection(
			to: pasteboard,
			type: .string
		))
		#expect(pasteboard.string(forType: .string) == source)
	}

	@Test func invalidAndBudgetedInlineMathKeepSourceAndInlineGeometry() throws
	{
		_ = NSApplication.shared
		for formula in [#"\(\unknownCommand{x}\)"#, #"\(x^2\)"#]
		{
			let parsed = MarkdownContentParser.parse(
				formula,
				markdown: true
			)
			let rendered = MarkdownAttributedStringRenderer.render(
				parsed.runs,
				richBlockMaximumPixels: 0
			)
			let attachment = try #require(rendered.attribute(
				.attachment,
				at: 0,
				effectiveRange: nil
			) as? MarkdownInlineMathAttachment)
			#expect(!attachment.rendersNativeImage)
			#expect(attachment.source == formula)
			#expect(rendered.attribute(
				.markdownSourceText,
				at: 0,
				effectiveRange: nil
			)
				as? String == formula)
			let cell = try #require(attachment.attachmentCell)
			#expect(cell.cellSize().width < 520)
		}
	}
}
