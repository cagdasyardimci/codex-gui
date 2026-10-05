import AppKit

@MainActor
final class TaskDeletionConfirmationButton: NSButton
{
	private static let cornerRadius: CGFloat = 10
	var isDestructive = false

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let outline = roundedOutline()
		let background = isDestructive
			? NSColor.systemRed.withAlphaComponent(0.1) : DesktopTheme.canvas
		background.setFill()
		outline.fill()

		if !isDestructive
		{
			DesktopTheme.border.setStroke()
			outline.lineWidth = 1
			outline.stroke()
		}
		if cell?.isHighlighted == true
		{
			NSColor.labelColor.withAlphaComponent(0.06).setFill()
			outline.fill()
		}

		let attributes: [NSAttributedString.Key: Any] = [
			.font: font ?? NSFont.systemFont(ofSize: 14),
			.foregroundColor: isDestructive ? NSColor.systemRed : NSColor.labelColor,
		]
		let titleSize = (title as NSString).size(withAttributes: attributes)
		(title as NSString).draw(
			at: NSPoint(
				x: bounds.midX - titleSize.width / 2,
				y: bounds.midY - titleSize.height / 2
			),
			withAttributes: attributes
		)
	}

	override var focusRingMaskBounds: NSRect
	{
		bounds
	}

	override func drawFocusRingMask()
	{
		roundedOutline().fill()
	}

	private func roundedOutline() -> NSBezierPath
	{
		NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: Self.cornerRadius,
			yRadius: Self.cornerRadius
		)
	}
}
