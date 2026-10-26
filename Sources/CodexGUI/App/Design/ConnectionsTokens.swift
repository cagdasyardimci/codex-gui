import AppKit

extension ShapeTokens
{
	enum Connections
	{
		static let cardRadius: CGFloat = 20
		static let pairingFrameRadius: CGFloat = 24
		static let modalRadius: CGFloat = 25
		static let fullscreenRadius: CGFloat = 48
		static let curve = CornerCurve.superellipse(1.5)
	}
}

extension TypographyTokens
{
	enum Connections
	{
		static let title = Role(
			size: 28,
			selection: .interface(weight: 500),
			lineHeight: 33.6
		)
		static let modalTitle = Role(
			size: 20,
			selection: .interface(weight: 500),
			lineHeight: 28
		)
		static let section = Role(
			size: 14,
			selection: .interface(weight: 500),
			lineHeight: 21
		)
		static let rowLabel = Role(
			size: 13,
			selection: .interface(weight: 500),
			lineHeight: 18.5714
		)
		static let body = Role(
			size: 13,
			lineHeight: 18.5714
		)
		static let caption = Role(
			size: 12,
			lineHeight: 16
		)
	}
}

extension AppKitColorTokens
{
	static let connectionsCard = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x232323
	)
	static let connectionsEdge = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF,
		lightAlpha: 0.08,
		darkAlpha: 0.082
	)
	static let pairingEdge = NSColor.labelColor.withAlphaComponent(0.0576)
	static let connectionsSecondaryHover = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF,
		lightAlpha: 0.1,
		darkAlpha: 0.1
	)
	static let connectionsSwitchOn = AppKitColorResolution.color(
		light: 0x0169CC,
		dark: 0x3A83F7
	)
	static let pairingSegmentTrack = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF,
		lightAlpha: 0.05,
		darkAlpha: 0.05
	)
	static let pairingSegmentSelected = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let pairingQR = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x181818
	)
	static let fullscreenQR = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let pairingQRInk = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF
	)
}
