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
			AppKitColorTokens.rowHighlight.setFill()
			selectionPath.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		let path = selectionPath
		AppKitColorTokens.rowHighlight.setFill()
		path.fill()
		if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		{
			NSColor.secondaryLabelColor.setStroke()
			let outline = NSBezierPath(
				roundedRect: selectionRect.insetBy(
					dx: ShapeTokens.SidebarSelection.outlineInset,
					dy: ShapeTokens.SidebarSelection.outlineInset
				),
				xRadius: ShapeTokens.SidebarSelection.outlineRadius,
				yRadius: ShapeTokens.SidebarSelection.outlineRadius
			)
			outline.lineWidth = ShapeTokens.SidebarSelection.outlineWidth
			outline.stroke()
		}
	}
	private var selectionRect: NSRect
	{
		NSRect(
			x: bounds.minX,
			y: bounds.minY,
			width: bounds.width,
			height: min(
				bounds.height,
				NavigationSidebarLayout.rowHeight
			)
		)
	}
	private var selectionPath: NSBezierPath
	{
		NSBezierPath(
			roundedRect: selectionRect,
			xRadius: ShapeTokens.SidebarSelection.cornerRadius,
			yRadius: ShapeTokens.SidebarSelection.cornerRadius
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
