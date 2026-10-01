import AppKit

@MainActor
final class FullAccessConfirmationButton: NSButton
{
	var confirmsFullAccess = false

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let background = confirmsFullAccess
			? NSColor.systemRed.withAlphaComponent(0.1) : DesktopTheme.input
		background.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: 18,
			yRadius: 18
		).fill()
		if cell?.isHighlighted == true
		{
			NSColor.labelColor.withAlphaComponent(0.06).setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: 18,
				yRadius: 18
			).fill()
		}
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font ?? NSFont.systemFont(ofSize: 14),
			.foregroundColor: confirmsFullAccess ? NSColor.systemRed : NSColor.labelColor,
		]
		let titleSize = (title as NSString).size(withAttributes: attributes)
		let iconWidth: CGFloat = confirmsFullAccess ? 14 : 0
		let spacing: CGFloat = confirmsFullAccess ? 6 : 0
		let originX = bounds.midX - (titleSize.width + iconWidth + spacing) / 2
		if confirmsFullAccess
		{
			image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
				paletteColors: [.systemRed]
			))?.draw(in: NSRect(
				x: originX,
				y: bounds.midY - 7,
				width: iconWidth,
				height: 14
			))
		}
		(title as NSString).draw(
			at: NSPoint(
				x: originX + iconWidth + spacing,
				y: bounds.midY - titleSize.height / 2
			),
			withAttributes: attributes
		)
	}
}
