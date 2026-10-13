import AppKit

/// Rounded hover feedback without replacing AppKit's action, focus or accessibility handling.
@MainActor
class DesktopHoverButton: DesktopAttributedTitleButton
{
	var cornerRadius: CGFloat = 12.5
	private var hovered = false
	private var tracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let tracking
		{
			removeTrackingArea(tracking)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent)
	{
		hovered = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		hovered = false
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isEnabled && (hovered || isHighlighted)
		{
			AppKitColorTokens.rowHighlight.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: cornerRadius,
				yRadius: cornerRadius
			).fill()
		}
		super.draw(dirtyRect)
	}
}
