import AppKit

final class ConversationSidebarRowView: NSTableRowView
{
	var isProjectRow = false
	var isTaskRow = false
	private(set) var isHovered = false
	private var hoverTrackingArea: NSTrackingArea?

	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawBackground(in dirtyRect: NSRect)
	{
		super.drawBackground(in: dirtyRect)
		let shouldDrawHoverBackground = (isTaskRow || isProjectRow) && isHovered && !isSelected
		if shouldDrawHoverBackground
		{
			AppKitColorTokens.rowHighlight.setFill()
			selectionPath.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		guard !isProjectRow || isHovered
		else
		{
			return
		}
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
		guard isTaskRow || isProjectRow
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
		if let window
		{
			let pointer = convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			)
			setHovered(window.isKeyWindow && visibleRect.contains(pointer))
		}
		else
		{
			setHovered(false)
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		setHovered(true)
	}

	override func mouseExited(with event: NSEvent)
	{
		setHovered(false)
	}

	private func setHovered(_ hovered: Bool)
	{
		isHovered = hovered
		for cell in subviews.compactMap(
			{
				$0 as? ProjectSidebarCellView
			}
		)
		{
			cell.setHovered(hovered)
		}
		needsDisplay = true
	}

}
