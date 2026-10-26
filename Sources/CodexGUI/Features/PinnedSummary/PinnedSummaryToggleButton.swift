import AppKit

@MainActor
final class PinnedSummaryToggleButton: NSButton
{
	private var hoverTrackingArea: NSTrackingArea?
	private(set) var isHovered = false

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverTrackingArea = area
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

	override func draw(_ dirtyRect: NSRect)
	{
		if state == .on || isHovered || isHighlighted
		{
			AppKitColorTokens.toggleHighlight.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: ShapeTokens.Toolbar.summaryToggleRadius,
				yRadius: ShapeTokens.Toolbar.summaryToggleRadius
			).fill()
		}
		super.draw(dirtyRect)
	}
}
