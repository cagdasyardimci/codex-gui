import AppKit

extension LayoutTokens
{
	enum Button
	{
		static let compactHeight: CGFloat = 24
		static let regularHeight: CGFloat = 32
		static let regularMinimumWidth: CGFloat = 78
		static let compactHorizontalInset: CGFloat = 9
		static let regularHorizontalInset: CGFloat = 16
		static let compactIconSize: CGFloat = 26
		static let regularIconSize: CGFloat = 32
		static let artworkSize: CGFloat = 16
		static let progressAllowance: CGFloat = 16
		static let progressSize: CGFloat = 12
		static let progressInset: CGFloat = 8
		static let menuChevronSize: CGFloat = 12
		static let menuChevronSpacing: CGFloat = 6
		static let tabHeight: CGFloat = 28
		static let overlayIconSize: CGFloat = 32
		static let diagramIconSize: CGFloat = 40
		static let zoomStepSize: CGFloat = 36
		static let imageZoomWidth: CGFloat = 64
	}
}

extension ShapeTokens
{
	enum Button
	{
		static let regularRadius: CGFloat = 10
		static let tabRadius: CGFloat = 12.5
		static let iconRadius: CGFloat = 10
		static let outlineWidth: CGFloat = 1
		static let overlayInset: CGFloat = 1
	}
}

extension TypographyTokens
{
	enum Button
	{
		static let compact = Role(
			size: 13,
			lineHeight: 18.5714
		)
		static let regular = Role(
			size: 14,
			lineHeight: 20
		)
		static let zoomStep = Role(size: 20)
	}
}

extension AppKitColorTokens
{
	static let buttonPrimarySurface = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF
	)
	static let buttonPrimaryText = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x0D0D0D
	)
	static let buttonSecondarySurface = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let buttonSecondaryEdge = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF,
		lightAlpha: 0.12,
		darkAlpha: 0.16
	)
	static let buttonDestructiveText = AppKitColorResolution.color(
		light: 0xE02E2A,
		dark: 0xFF6764
	)
}
