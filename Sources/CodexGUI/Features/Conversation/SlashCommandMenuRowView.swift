import AppKit

@MainActor
final class SlashCommandMenuRowView: NSTableRowView
{
	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		drawHighlight()
	}

	private func drawHighlight()
	{
		DesktopTheme.slashMenuSelection.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: 14,
			yRadius: 14
		).fill()
	}
}
