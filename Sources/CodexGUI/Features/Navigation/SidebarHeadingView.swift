import AppKit

@MainActor
final class SidebarHeadingView: NSStackView
{
	var hoverButtons: [NSButton] = []
	{
		didSet
		{
			updateHover(false)
		}
	}

	private var hoverTrackingArea: NSTrackingArea?
	private var isHovered = false

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let tracking = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
			updateHover(visibleRect.contains(pointer))
		}
		else
		{
			updateHover(false)
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		updateHover(true)
	}

	override func mouseExited(with event: NSEvent)
	{
		updateHover(false)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isHovered && !hoverButtons.isEmpty
		{
			AppKitColorTokens.rowHighlight.setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: ShapeTokens.SidebarSelection.cornerRadius,
				curve: ShapeTokens.SidebarSelection.cornerCurve
			).fill()
		}
		super.draw(dirtyRect)
	}

	private func updateHover(_ hovered: Bool)
	{
		isHovered = hovered
		for button in hoverButtons
		{
			button.isHidden = !hovered
		}
		needsDisplay = true
	}
}
