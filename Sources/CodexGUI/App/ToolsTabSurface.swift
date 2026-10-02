import AppKit

@MainActor
final class ToolsTabSurface: NSView
{
	private let isSelected: Bool
	private var isHovered = false
	private var hoverTrackingArea: NSTrackingArea?

	init(isSelected: Bool)
	{
		self.isSelected = isSelected
		super.init(frame: .zero)
		setAccessibilityElement(false)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

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
		if let window
		{
			isHovered = bounds.contains(convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
		needsDisplay = true
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

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard isSelected || isHovered
		else
		{
			return
		}
		let inset: CGFloat = isSelected ? 0.5 : 0
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: inset,
				dy: inset
			),
			xRadius: 8,
			yRadius: 8
		)
		DesktopTheme.input.setFill()
		path.fill()
		if isSelected
		{
			DesktopTheme.highlightedPaneDivider.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
}
