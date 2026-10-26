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
		static let rowHeight = LayoutTokens.MenuRow.height
		static let profileHeight: CGFloat = 42.5703125
		static let separatorHeight: CGFloat = 9
		static let shadowOutset: CGFloat = 24
		static let height = 2 * gutter + profileHeight + 3 * rowHeight + 2 * separatorHeight
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
		static let row = Role(
			size: 13,
			selection: .interface(weight: 430),
			lineHeight: 18.5703125
		)
		static let subtitle = Role(
			size: 12,
			selection: .interface(weight: 430),
			lineHeight: 14
		)
	}
}

extension AppKitColorTokens
{
	static let accountMenuRowHighlight = AppKitColorResolution.color(
		light: 0x0D0D0D,
		dark: 0xFFFFFF,
		lightAlpha: 0.055,
		darkAlpha: 0.08
	)
	static let accountAvatar = NSColor(
		srgbRed: 0.20,
		green: 0.28,
		blue: 0.34,
		alpha: 1
	)
}
