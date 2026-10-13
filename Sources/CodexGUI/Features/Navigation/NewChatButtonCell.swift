import AppKit

final class NewChatButtonCell: NSButtonCell
{
	override func drawTitle(
		_ title: NSAttributedString,
		withFrame frame: NSRect,
		in controlView: NSView
	) -> NSRect
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.drawTitle(
				title,
				withFrame: frame,
				in: controlView
			)
		}
	}

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		var titleRect = super.titleRect(forBounds: rect)
		let titleLeading = imageRect(forBounds: rect).maxX + 8
		titleRect.origin.x = titleLeading
		titleRect.size.width = max(
			0,
			rect.maxX - titleLeading
		)
		return titleRect
	}
}
