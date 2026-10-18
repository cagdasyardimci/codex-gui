import AppKit

@MainActor
final class ConversationBodyMeasurer
{
	private let storage = NSTextStorage()
	private let layout = MarkdownLayoutManager()
	private let container = NSTextContainer(
		size: NSSize(
			width: 1,
			height: CGFloat.greatestFiniteMagnitude
		)
	)
	private weak var text: NSAttributedString?

	init()
	{
		container.lineFragmentPadding = 0
		layout.addTextContainer(container)
		storage.addLayoutManager(layout)
	}

	func height(
		of text: NSAttributedString,
		width: CGFloat
	) -> CGFloat
	{
		prepare(
			text,
			width: width
		)
		return max(
			1,
			ceil(layout.usedRect(for: container).height) + 2
		)
	}

	func readingAnchor(
		of text: NSAttributedString,
		atY y: CGFloat,
		width: CGFloat
	) -> (character: Int, offset: CGFloat)?
	{
		prepare(
			text,
			width: width
		)
		guard layout.numberOfGlyphs > 0, y >= 0, y <= layout.usedRect(for: container).maxY
		else
		{
			return nil
		}
		let glyph = min(
			layout.numberOfGlyphs - 1,
			layout.glyphIndex(
				for: NSPoint(
					x: 0,
					y: y
				),
				in: container
			)
		)
		let line = layout.lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		)
		return (layout.characterIndexForGlyph(at: glyph), y - line.minY)
	}

	func lineOrigin(
		of text: NSAttributedString,
		atCharacter character: Int,
		width: CGFloat
	) -> CGFloat?
	{
		prepare(
			text,
			width: width
		)
		guard character >= 0, character < storage.length, layout.numberOfGlyphs > 0
		else
		{
			return nil
		}
		let glyph = layout.glyphIndexForCharacter(at: character)
		return layout.lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		).minY
	}

	private func prepare(
		_ text: NSAttributedString,
		width: CGFloat
	)
	{
		if self.text !== text
		{
			storage.setAttributedString(text)
			self.text = text
		}
		if container.size.width != width
		{
			container.size = NSSize(
				width: width,
				height: .greatestFiniteMagnitude
			)
		}
		layout.ensureLayout(for: container)
	}
}
