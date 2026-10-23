import AppKit

/// Retains NSButton activation and accessibility while drawing a circular close control.
@MainActor
final class ExpandedImageCloseButton: NSButton
{
	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)
	}

	var usesLightSurface = false
	private var hover = false
	private var hoverTracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		hoverTracking = ExpandedImageHeaderDrawing.updateTracking(
			view: self,
			previous: hoverTracking
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		hover = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		hover = false
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if usesLightSurface
		{
			NSColor.white.setFill()
			let circle = NSBezierPath(ovalIn: bounds.insetBy(
				dx: 1,
				dy: 1
			))
			circle.fill()
			if window?.firstResponder === self
			{
				NSColor.keyboardFocusIndicatorColor.setStroke()
				circle.lineWidth = 2
				circle.stroke()
			}
		}
		else
		{
			ExpandedImageHeaderDrawing.drawBackground(
				control: self,
				hover: hover
			)
		}
		let mark = NSBezierPath()
		let center = NSPoint(
			x: bounds.midX,
			y: bounds.midY
		)
		mark.move(to: NSPoint(
			x: center.x - 4,
			y: center.y - 4
		))
		mark.line(to: NSPoint(
			x: center.x + 4,
			y: center.y + 4
		))
		mark.move(to: NSPoint(
			x: center.x - 4,
			y: center.y + 4
		))
		mark.line(to: NSPoint(
			x: center.x + 4,
			y: center.y - 4
		))
		mark.lineWidth = 1.5
		mark.lineCapStyle = .round
		(usesLightSurface ? NSColor.darkGray
			: ExpandedImageHeaderDrawing.foreground(enabled: isEnabled)).setStroke()
		mark.stroke()
	}
}
