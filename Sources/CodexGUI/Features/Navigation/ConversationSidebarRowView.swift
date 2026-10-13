import AppKit

final class ConversationSidebarRowView: NSTableRowView
{
	var isCurrentProject = false
	var isTaskRow = false
	private var isHovered = false
	private var hoverTrackingArea: NSTrackingArea?

	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawBackground(in dirtyRect: NSRect)
	{
		super.drawBackground(in: dirtyRect)
		let shouldDrawCurrentProjectBackground = isCurrentProject && !isSelected
		let shouldDrawTaskHoverBackground = isTaskRow && isHovered && !isSelected
		if shouldDrawCurrentProjectBackground
		{
			drawSelection(in: dirtyRect)
		}
		else if shouldDrawTaskHoverBackground
		{
			AppKitColorTokens.selection.withAlphaComponent(0.55).setFill()
			selectionPath.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		let path = selectionPath
		AppKitColorTokens.selection.setFill()
		path.fill()
		if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		{
			NSColor.secondaryLabelColor.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
	private var selectionPath: NSBezierPath
	{
		NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: 7,
			yRadius: 7
		)
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		hoverTrackingArea = nil
		guard isTaskRow
		else
		{
			return
		}
		let tracking = NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeInKeyWindow,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(tracking)
		hoverTrackingArea = tracking
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		needsDisplay = true
	}

}
