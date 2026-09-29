import AppKit

final class ConversationSidebarRowView: NSTableRowView
{
	var isCurrentProject = false

	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawBackground(in dirtyRect: NSRect)
	{
		super.drawBackground(in: dirtyRect)
		if isCurrentProject && !isSelected
		{
			drawSelection(in: dirtyRect)
		}
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: 7,
			yRadius: 7
		)
		DesktopTheme.selection.setFill()
		path.fill()
		if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		{
			NSColor.secondaryLabelColor.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
}
