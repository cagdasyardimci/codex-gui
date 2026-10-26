import AppKit

/// Rounded hover feedback without replacing AppKit's action, focus or accessibility handling.
@MainActor
class DesktopHoverButton: DesktopAttributedTitleButton
{
	var cornerRadius: CGFloat = 12.5
	var cornerCurve: ShapeTokens.CornerCurve = .circular
	private(set) var isHovered = false
	private var tracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		clearHover()
	}

	func clearHover()
	{
		isHovered = false
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		drawBackground()
		super.draw(dirtyRect)
	}

	func drawBackground()
	{
		if isEnabled && (isHovered || isHighlighted)
		{
			AppKitColorTokens.rowHighlight.setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: cornerRadius,
				curve: cornerCurve
			).fill()
		}
	}
}
