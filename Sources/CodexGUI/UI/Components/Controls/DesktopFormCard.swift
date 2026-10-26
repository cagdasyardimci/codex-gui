import AppKit

@MainActor
final class DesktopFormCard: NSView
{
	var isPairingFrame = false

	override func draw(_ dirtyRect: NSRect)
	{
		let path = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: isPairingFrame ? ShapeTokens.Connections
				.pairingFrameRadius
				: ShapeTokens.Connections.cardRadius,
			curve: ShapeTokens.Connections.curve
		)
		if !isPairingFrame
		{
			AppKitColorTokens.connectionsCard.setFill()
			path.fill()
		}
		(isPairingFrame ? AppKitColorTokens.pairingEdge : AppKitColorTokens.connectionsEdge)
			.setStroke()
		path.stroke()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}
