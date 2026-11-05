import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct MarkdownInlineCodeBackgroundTests
{
	@Test(arguments: [CGFloat(0), CGFloat(18)])
	func backgroundCentersOnCodeInkDespiteLineSpacing(_ spacing: CGFloat) throws
	{
		let content = NSMutableAttributedString(attributedString: MarkdownAttributedStringRenderer
			.render(
				MarkdownContentParser.parse(
					"Full `MAKE CHECK` passed.\n\nNext paragraph.",
					markdown: true
				).runs
			))
		let fullRange = NSRange(
			location: 0,
			length: content.length
		)
		content.enumerateAttribute(
			.paragraphStyle,
			in: fullRange
		)
		{
			value, range, _ in
			let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
			paragraph?.lineSpacing = spacing
			if let paragraph
			{
				content.addAttribute(
					.paragraphStyle,
					value: paragraph,
					range: range
				)
			}
		}
		let storage = NSTextStorage(attributedString: content)
		let manager = MarkdownLayoutManager()
		let container = NSTextContainer(containerSize: NSSize(
			width: 400,
			height: 200
		))
		storage.addLayoutManager(manager)
		manager.addTextContainer(container)
		manager.ensureLayout(for: container)
		let code = (content.string as NSString).range(of: "MAKE\u{00A0}CHECK")
		try #require(code.location != NSNotFound)
		let glyphs = manager.glyphRange(
			forCharacterRange: code,
			actualCharacterRange: nil
		)
		let background = try rasterBounds
		{
			manager.drawBackground(
				forGlyphRange: manager.glyphRange(for: container),
				at: NSPoint(
					x: 10,
					y: 10
				)
			)
		}
		let line = CTLineCreateWithAttributedString(content.attributedSubstring(from: code))
		let ink = CTLineGetImageBounds(
			line,
			nil
		)
		let fragment = manager.lineFragmentRect(
			forGlyphAt: glyphs.location,
			effectiveRange: nil
		)
		let baseline = 10 + fragment.minY + manager.location(forGlyphAt: glyphs.location).y
		let inkTop = baseline - ink.maxY
		let inkBottom = baseline - ink.minY
		#expect(abs(background.midY - (inkTop + inkBottom) / 2) <= 1)
		#expect(background.minY < inkTop)
		#expect(background.maxY > inkBottom)
	}

	private func rasterBounds(_ draw: @escaping () -> Void) throws -> NSRect
	{
		let image = NSImage(
			size: NSSize(
				width: 420,
				height: 220
			),
			flipped: true
		)
		{
			_ in
			draw()
			return true
		}
		let data = try #require(image.tiffRepresentation)
		let bitmap = try #require(NSBitmapImageRep(data: data))
		var bounds = NSRect.null
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide
			{
				if let color = bitmap.colorAt(
					x: x,
					y: y
				), color.alphaComponent > 0.02
				{
					bounds = bounds.union(NSRect(
						x: x,
						y: y,
						width: 1,
						height: 1
					))
				}
			}
		}
		#expect(!bounds.isNull)
		return bounds
	}
}
