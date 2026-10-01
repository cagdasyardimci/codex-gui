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
		drawBackground()
		drawTitleAndWarningIcon()
	}

	private func drawBackground()
	{
		let background = confirmsFullAccess
			? NSColor.systemRed.withAlphaComponent(0.1) : DesktopTheme.input
		let backgroundPath = NSBezierPath(
			roundedRect: bounds,
			xRadius: 18,
			yRadius: 18
		)
		background.setFill()
		backgroundPath.fill()

		if cell?.isHighlighted == true
		{
			NSColor.labelColor.withAlphaComponent(0.06).setFill()
			backgroundPath.fill()
		}
	}

	private func drawTitleAndWarningIcon()
	{
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font ?? NSFont.systemFont(ofSize: 14),
			.foregroundColor: confirmsFullAccess ? NSColor.systemRed : NSColor.labelColor,
		]
		let titleSize = (title as NSString).size(withAttributes: attributes)
		let iconWidth: CGFloat = confirmsFullAccess ? 14 : 0
		let iconToTitleSpacing: CGFloat = confirmsFullAccess ? 6 : 0
		let contentWidth = titleSize.width + iconWidth + iconToTitleSpacing
		let contentOriginX = bounds.midX - contentWidth / 2

		if confirmsFullAccess
		{
			DesktopIcons.draw(
				.triangleExclamationErrorWarning,
				in: NSRect(
					x: contentOriginX,
					y: bounds.midY - 7,
					width: iconWidth,
					height: 14
				),
				tint: .systemRed
			)
		}
		(title as NSString).draw(
			at: NSPoint(
				x: contentOriginX + iconWidth + iconToTitleSpacing,
				y: bounds.midY - titleSize.height / 2
			),
			withAttributes: attributes
		)
	}
}
