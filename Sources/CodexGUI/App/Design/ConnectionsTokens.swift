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
			rule: .heading(28),
			selection: .interface(weight: .medium),
			lineHeight: .multiple(1.2)
		)
		static let modalTitle = TypographyTokens.Text.heading(
			20,
			weight: .medium
		)
		static let section = Role(
			rule: .ui(offset: 0),
			selection: .interface(weight: .medium),
			lineHeight: .multiple(1.5)
		)
		static let rowLabel = TypographyTokens.Text.rowLabel
		static let body = TypographyTokens.Text.menu
		static let caption = TypographyTokens.Text.captionLine
	}
}

extension AppKitColorTokens
{
	static var connectionsCard: NSColor
	{
		paletteColor
		{
			$0.elevatedSecondary
		}
	}
	static var connectionsEdge: NSColor
	{
		border
	}
	static var pairingEdge: NSColor
	{
		border
	}
	static var connectionsSecondaryHover: NSColor
	{
		hoverOverlay
	}
	static var connectionsSwitchOn: NSColor
	{
		accent
	}
	static var pairingSegmentTrack: NSColor
	{
		hoverOverlay
	}
	static var pairingSegmentSelected: NSColor
	{
		elevatedOpaque
	}
	static var pairingQR: NSColor
	{
		paletteColor
		{
			$0.qrSurface
		}
	}
	static var fullscreenQR: NSColor
	{
		paletteColor
		{
			$0.fullscreenQRSurface
		}
	}
	static var pairingQRInk: NSColor
	{
		paletteColor
		{
			$0.qrInk
		}
	}
	static var fullscreenQRInk: NSColor
	{
		paletteColor
		{
			$0.fullscreenQRInk
		}
	}

}
