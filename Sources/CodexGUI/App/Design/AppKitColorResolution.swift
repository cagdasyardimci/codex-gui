import AppKit

/// Native color construction and resolution without knowledge of named roles.
@MainActor
enum AppKitColorResolution
{
	static func adaptiveColor(_ provider: @escaping (NSAppearance) -> NSColor) -> NSColor
	{
		NSColor(
			name: nil,
			dynamicProvider: provider
		)
	}

	/// Layer colors must be resolved again whenever their owning view's appearance changes.
	static func resolvedCGColor(
		_ color: NSColor,
		for view: NSView,
		alpha: CGFloat? = nil
	) -> CGColor
	{
		var resolvedColor: CGColor!
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			if let alpha
			{
				resolvedColor = color.withAlphaComponent(alpha).cgColor
			}
			else
			{
				resolvedColor = color.cgColor
			}
		}
		return resolvedColor
	}

	static func color(
		light: UInt32,
		dark: UInt32,
		lightAlpha: CGFloat = 1,
		darkAlpha: CGFloat = 1
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			let rgbHexValue = isDark ? dark : light
			return NSColor(
				srgbRed: CGFloat((rgbHexValue >> 16) & 0xFF) / 255,
				green: CGFloat((rgbHexValue >> 8) & 0xFF) / 255,
				blue: CGFloat(rgbHexValue & 0xFF) / 255,
				alpha: isDark ? darkAlpha : lightAlpha
			)
		}
	}
	static func grayscaleColor(
		light: CGFloat,
		dark: CGFloat
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			NSColor(
				white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
					? dark : light,
				alpha: 1
			)
		}
	}

}
