import AppKit

@MainActor
final class FullAccessConfirmationButton: NSButton
{
	private enum LayoutMetrics
	{
		static let cornerRadius: CGFloat = 18
		static let warningIconSize: CGFloat = 14
		static let iconToTitleSpacing: CGFloat = 6
	}

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
			xRadius: LayoutMetrics.cornerRadius,
			yRadius: LayoutMetrics.cornerRadius
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
		let iconWidth: CGFloat = confirmsFullAccess ? LayoutMetrics.warningIconSize : 0
		let iconToTitleSpacing: CGFloat = confirmsFullAccess ? LayoutMetrics.iconToTitleSpacing : 0
		let contentWidth = titleSize.width + iconWidth + iconToTitleSpacing
		let contentOriginX = bounds.midX - contentWidth / 2

		if confirmsFullAccess
		{
			DesktopIcons.draw(
				.triangleExclamationErrorWarning,
				in: NSRect(
					x: contentOriginX,
					y: bounds.midY - LayoutMetrics.warningIconSize / 2,
					width: iconWidth,
					height: LayoutMetrics.warningIconSize
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
