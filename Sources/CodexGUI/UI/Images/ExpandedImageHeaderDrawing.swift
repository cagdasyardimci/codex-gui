import AppKit

@MainActor
enum ExpandedImageHeaderDrawing
{
	static func foreground(
		enabled: Bool,
		lightSurface: Bool = false
	) -> NSColor
	{
		(lightSurface ? NSColor.darkGray : .white).withAlphaComponent(enabled ? 0.9 : 0.4)
	}

	static func drawBackground(
		control: NSButton,
		hover: Bool,
		lightSurface: Bool = false
	)
	{
		let pressed = control.cell?.isHighlighted == true
		let opacity: CGFloat = pressed ? 0.24 : (hover && control.isEnabled ? 0.18 : 0.12)
		(lightSurface ? NSColor.white.withAlphaComponent(control.isEnabled ? 1 : 0.4)
			: NSColor.white.withAlphaComponent(opacity)).setFill()
		let shape = NSBezierPath(
			roundedRect: control.bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: control.bounds.height / 2,
			yRadius: control.bounds.height / 2
		)
		shape.fill()
		if control.window?.firstResponder === control
		{
			NSColor.keyboardFocusIndicatorColor.setStroke()
			shape.lineWidth = 2
			shape.stroke()
		}
	}


	static func updateTracking(
		view: NSView,
		previous: NSTrackingArea?
	) -> NSTrackingArea
	{
		if let previous
		{
			view.removeTrackingArea(previous)
		}
		let tracking = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: view,
			userInfo: nil
		)
		view.addTrackingArea(tracking)
		return tracking
	}
}
