import AppKit

/// Keeps the native popup menu and keyboard behavior while drawing the viewer's zoom pill.
@MainActor
final class ExpandedImageZoomButton: DesktopPopupButton
{
	override init(
		frame buttonFrame: NSRect,
		pullsDown flag: Bool
	)
	{
		super.init(
			frame: buttonFrame,
			pullsDown: flag
		)
		isBordered = false
		focusRingType = .none
		font = AppKitFontResolver.font(TypographyTokens.Button.compact)
		toolTip = "Zoom"
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: LayoutTokens.Button.imageZoomWidth,
			height: LayoutTokens.Button.regularHeight
		)
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)
	}

	private var hover = false
	private var hoverTracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		hoverTracking = DesktopHoverTracking.replace(
			in: self,
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
		ExpandedImageHeaderDrawing.drawBackground(
			control: self,
			hover: hover
		)
		let title = selectedItem?.title ?? ""
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 13),
			.foregroundColor: ExpandedImageHeaderDrawing.foreground(enabled: isEnabled)
		]
		let size = (title as NSString).size(withAttributes: attributes)
		(title as NSString).draw(
			at: NSPoint(
				x: (bounds.width - 16 - size.width) / 2,
				y: bounds.midY - size.height / 2
			),
			withAttributes: attributes
		)
		let direction: CGFloat = isFlipped ? -1 : 1
		let chevron = NSBezierPath()
		chevron.move(to: NSPoint(
			x: bounds.maxX - 17,
			y: bounds.midY + 2 * direction
		))
		chevron.line(to: NSPoint(
			x: bounds.maxX - 14,
			y: bounds.midY - 2 * direction
		))
		chevron.line(to: NSPoint(
			x: bounds.maxX - 11,
			y: bounds.midY + 2 * direction
		))
		chevron.lineWidth = 1.5
		chevron.lineCapStyle = .round
		ExpandedImageHeaderDrawing.foreground(enabled: isEnabled).setStroke()
		chevron.stroke()
	}
}
