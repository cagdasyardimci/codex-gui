import AppKit

/// Rounded hover feedback without replacing AppKit's action, focus or accessibility handling.
@MainActor
class DesktopHoverButton: DesktopAttributedTitleButton
{
	var cornerRadius: CGFloat = 12.5
	var cornerCurve: ShapeTokens.CornerCurve = .circular
	private(set) var isHovered = false
	var hoverBackgroundColor: NSColor
	{
		AppKitColorTokens.rowHighlight
	}
	var hoverTrackingOptions: NSTrackingArea.Options
	{
		[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
	}
	var synchronizesHoverOnTrackingUpdate: Bool
	{
		false
	}
	var isBackgroundHighlighted: Bool
	{
		isEnabled && (isHovered || isHighlighted)
	}
	private var tracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking,
			options: hoverTrackingOptions
		)
		if synchronizesHoverOnTrackingUpdate
		{
			setHovered(window.map
			{
				visibleRect.contains(convert(
					$0.mouseLocationOutsideOfEventStream,
					from: nil
				))
			} ?? false)
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		setHovered(true)
	}

	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		clearHover()
	}

	func clearHover()
	{
		setHovered(false)
	}

	func setHovered(_ hovered: Bool)
	{
		isHovered = hovered
		needsDisplay = true
		hoverDidChange()
	}

	func hoverDidChange()
	{
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
		if isBackgroundHighlighted
		{
			hoverBackgroundColor.setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: cornerRadius,
				curve: cornerCurve
			).fill()
		}
	}
}
