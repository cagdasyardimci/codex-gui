import AppKit

@MainActor
final class SlashCommandMenuRowView: NSTableRowView
{
	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	var isHovered = false
	{
		didSet
		{
			if isHovered != oldValue
			{
				needsDisplay = true
			}
		}
	}

	override func drawBackground(in dirtyRect: NSRect)
	{
		if isHovered && !isSelected
		{
			drawHighlight()
		}
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
