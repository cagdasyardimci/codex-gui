import AppKit

@MainActor
final class ProjectRenameButton: NSButton
{
	var isPrimary = false
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
	override func draw(_ dirtyRect: NSRect)
	{
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 10,
			yRadius: 10
		)
		(isPrimary ? NSColor.textColor : AppKitColorTokens.elevated).setFill()
		outline.fill()
		if !isPrimary
		{
			AppKitColorTokens.border.setStroke()
			outline.lineWidth = 1
			outline.stroke()
		}
		if cell?.isHighlighted == true
		{
			NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
			outline.fill()
		}
		let foreground = isPrimary ? NSColor.textBackgroundColor : NSColor.labelColor
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font ?? NSFont.systemFont(ofSize: 14),
			.foregroundColor: isEnabled ? foreground : foreground.withAlphaComponent(0.4),
		]
		let size = (title as NSString).size(withAttributes: attributes)
		(title as NSString).draw(
			at: NSPoint(
				x: bounds.midX - size.width / 2,
				y: bounds.midY - size.height / 2
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
		NSBezierPath(
			roundedRect: bounds,
			xRadius: 10,
			yRadius: 10
		).fill()
	}
}
