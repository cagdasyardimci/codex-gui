import AppKit

@MainActor
final class DesktopFormCard: NSView
{
	var isPairingFrame = false
	var isSettingsCard = false
	private lazy var colorObservation = ThemeColorObservation
	{
		[weak self] in self?.needsDisplay = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		_ = colorObservation
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let path = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: isPairingFrame ? ShapeTokens.Connections
				.pairingFrameRadius
				:
				(isSettingsCard ? ShapeTokens.Settings.cardRadius : ShapeTokens.Connections
					.cardRadius),
			curve: ShapeTokens.Connections.curve
		)
		if !isPairingFrame
		{
			(isSettingsCard ? AppKitColorTokens.settingsCard : AppKitColorTokens.connectionsCard)
				.setFill()
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
