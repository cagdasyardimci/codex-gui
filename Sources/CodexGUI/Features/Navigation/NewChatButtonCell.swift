import AppKit

final class NewChatButtonCell: NSButtonCell
{
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
