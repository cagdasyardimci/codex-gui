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

	override func imageRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.minX + NavigationSidebarLayout.cellInset,
			y: rect.midY - NavigationSidebarLayout.iconSize / 2,
			width: NavigationSidebarLayout.iconSize,
			height: NavigationSidebarLayout.iconSize
		)
	}

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		let titleLeading = imageRect(forBounds: rect).maxX
			+ NavigationSidebarLayout.iconTextSpacing
		return NSRect(
			x: titleLeading,
			y: rect.midY - LayoutTokens.SidebarSelection.newChatTitleHeight / 2,
			width: max(
				0,
				rect.maxX - titleLeading - NavigationSidebarLayout.cellInset
			),
			height: LayoutTokens.SidebarSelection.newChatTitleHeight
		)
	}
}
