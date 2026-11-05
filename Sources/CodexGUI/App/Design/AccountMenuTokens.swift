import AppKit

extension LayoutTokens
{
	/// Measured account-menu geometry from the ChatGPT desktop reference.
	enum AccountMenu
	{
		static let width: CGFloat = 228
		static let gutter: CGFloat = 4
		static let horizontalInset: CGFloat = 8
		static let iconSize: CGFloat = 16
		static let iconSpacing: CGFloat = 6
		static let avatarSize: CGFloat = 18
		static var rowHeight: CGFloat
		{
			LayoutTokens.MenuRow.height
		}
		static let profileHeight: CGFloat = 42.5703125
		static let separatorHeight: CGFloat = 9
		static let shadowOutset: CGFloat = 24
		static var height: CGFloat
		{
			2 * gutter + profileHeight + 3 * rowHeight + 2 * separatorHeight
		}
	}
}

extension ShapeTokens
{
	enum AccountMenu
	{
		static let rowRadius: CGFloat = 15
		static let cornerCurve = CornerCurve.superellipse(1.5)
	}
}

extension TypographyTokens
{
	enum AccountMenu
	{
		static let row = TypographyTokens.Text.menu
		static let subtitle = TypographyTokens.MenuRow.subtitle
	}
}

extension AppKitColorTokens
{
	static var accountMenuRowHighlight: NSColor
	{
		hoverOverlay
	}
	static var accountAvatar: NSColor
	{
		accentSurface
	}
}
