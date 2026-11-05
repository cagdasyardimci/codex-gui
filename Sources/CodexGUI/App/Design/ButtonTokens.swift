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
		static let contentSpacing: CGFloat = 6
		static let miniIconSize: CGFloat = 20
		static let smallIconSize: CGFloat = 24
		static let searchIconSize: CGFloat = 28
		static let progressAllowance: CGFloat = 16
		static let progressSize: CGFloat = 12
		static let progressInset: CGFloat = 8
		static let menuChevronSize: CGFloat = 12
		static let menuChevronSpacing: CGFloat = 6
		static let tabHeight: CGFloat = 28
		static let overlayIconSize: CGFloat = 32
		static let diagramIconSize: CGFloat = 40
		static let diagramCloseWidth: CGFloat = 42
		static let zoomStepSize: CGFloat = 36
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
		static let compact = TypographyTokens.Text.button(compact: true)
		static let regular = TypographyTokens.Text.button(compact: false)
		static let dialog = TypographyTokens.Text.action
		// Header value pickers use detail text in the regular control line box.
		static let value = Role(
			rule: TypographyTokens.Text.detail.sizeRule,
			lineHeight: TypographyTokens.Text.control.lineHeightRule
		)
		// The zoom symbol is fitted to a fixed artwork slot rather than a text line.
		static let zoomStep = Role(rule: .fixed(20))
	}
}

extension AppKitColorTokens
{
	static var buttonPrimarySurface: NSColor
	{
		foreground
	}
	static var buttonPrimaryText: NSColor
	{
		controlSurface
	}
	static var buttonDialogSecondarySurface: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.03)
		}
	}
	static var buttonSecondarySurface: NSColor
	{
		elevated
	}
	static var buttonSecondaryEdge: NSColor
	{
		heavyBorder
	}
	static var buttonDestructiveText: NSColor
	{
		errorText
	}
}
