import AppKit

/// Resolves the reference's custom RGB palette for a single appearance.
@MainActor
struct ColorPalette
{
	private struct RGB
	{
		let red: Double
		let green: Double
		let blue: Double

		init(_ hex: UInt32)
		{
			red = Double((hex >> 16) & 255)
			green = Double((hex >> 8) & 255)
			blue = Double(hex & 255)
		}

		init(
			red: Double,
			green: Double,
			blue: Double
		)
		{
			self.red = red
			self.green = green
			self.blue = blue
		}

		func mix(
			_ other: RGB,
			_ amount: Double
		) -> RGB
		{
			let t = min(
				1,
				max(
					0,
					amount
				)
			)
			return RGB(
				red: (red + (other.red - red) * t).rounded(),
				green: (green + (other.green - green) * t).rounded(),
				blue: (blue + (other.blue - blue) * t).rounded()
			)
		}

		func color(_ alpha: Double = 1) -> NSColor
		{
			let opacity = (min(
				1,
				max(
					0,
					alpha
				)
			) * 1000).rounded() / 1000
			return NSColor(
				srgbRed: red / 255,
				green: green / 255,
				blue: blue / 255,
				alpha: opacity
			)
		}

		func exactAlphaColor(_ alpha: Double) -> NSColor
		{
			NSColor(
				srgbRed: red / 255,
				green: green / 255,
				blue: blue / 255,
				alpha: alpha
			)
		}
	}

	private let profile: ColorThemeProfile
	private let dark: Bool
	private let q: Double
	private var background: RGB
	{
		RGB(profile.background)
	}
	private var ink: RGB
	{
		RGB(profile.foreground)
	}
	private var accentRGB: RGB
	{
		guard let name = profile.namedAccent
		else
		{
			return RGB(profile.accent)
		}
		return RGB(namedColors(name)[name == .purple ? 3 : 4])
	}
	private func namedColors(_ name: ColorNamedAccent) -> [UInt32]
	{
		switch name
		{
		case .default, .blue, .black: [
				0xF6FAFE,
				0xE8F3FE,
				0x63A8F8,
				0x539AF8,
				0x3A83F7,
				0x2C67C5,
				0x1F4E94,
				0x173E76,
				0x133463,
				0x0C274A
			]
		case .green: [
				0xEFFAF3,
				0xDEF3E5,
				0x83D197,
				0x6BC67F,
				0x53B559,
				0x48A04C,
				0x3A843F,
				0x2C6732,
				0x1F4E25,
				0x14361A
			]
		case .yellow: [
				0xFEFBEE,
				0xFDF6DC,
				0xF9DC78,
				0xF8D45D,
				0xF6C543,
				0xD9A337,
				0xB8802B,
				0x95611F,
				0x734615,
				0x51300C
			]
		case .pink: [
				0xFEF8FB,
				0xFDEDF4,
				0xF8A6C8,
				0xF68EBC,
				0xF077AF,
				0xCF6194,
				0xAB4F7A,
				0x873E60,
				0x663049,
				0x462132
			]
		case .orange: [
				0xFDF5F1,
				0xFBE8DB,
				0xF1A275,
				0xEF8B57,
				0xEE7C37,
				0xD25E28,
				0xAC4F23,
				0x87401D,
				0x653218,
				0x45240D
			]
		case .purple: [
				0xF8F5FD,
				0xEDE5FC,
				0xB897F4,
				0xA67DF2,
				0x8952EE,
				0x7849D1,
				0x643CAE,
				0x4E2F88,
				0x3B2366,
				0x291947
			]
		}
	}
	private var namedText: NSColor?
	{
		guard let name = profile.namedAccent
		else
		{
			return nil
		}
		let index = name == .yellow ? (dark ? 4 : 6) :
			(dark && (name == .pink || name == .orange) ? 4 : 5)
		return RGB(namedColors(name)[index]).color()
	}
	private var namedSurface: NSColor?
	{
		guard let name = profile.namedAccent
		else
		{
			return nil
		}
		return RGB(namedColors(name)[dark ? 8 : 1]).color()
	}
	private var white: RGB
	{
		RGB(0xFFFFFF)
	}
	private var black: RGB
	{
		RGB(0)
	}
	private var controlRGB: RGB
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.06 + 0.05 * q : 0.09 + 0.04 * q
		)
	}
	private var elevatedRGB: RGB
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.08 + 0.08 * q : 0.16 + 0.12 * q
		)
	}
	private var accentTextRGB: RGB
	{
		informationText(accentRGB)
	}
	private func informationText(_ blue: RGB) -> RGB
	{
		dark ? blue.mix(
			white,
			0.30 + 0.15 * q
		) : blue
	}

	init(
		configuration: ColorThemeProfile,
		mode: ColorAppearance
	)
	{
		profile = configuration
		dark = mode == .dark
		let value = Double(configuration.contrast)
		let baseline = mode == .dark ? 60.0 : 45.0
		let x = value / 100 + (value - baseline) / 60 * 0.7
		q = value <= baseline ? x : baseline / 100 + (x - baseline / 100) * 2
	}

	var surface: NSColor
	{
		background.color()
	}
	var surfaceUnder: NSColor
	{
		background.mix(
			dark ? black : ink,
			dark ? 0.16 + 0.0015 * (Double(profile.contrast) - 60) : 0.04 + 0.0012 *
				(Double(profile.contrast) - 45)
		).color()
	}
	var sidebarTint: NSColor
	{
		surface.withAlphaComponent(0.65)
	}
	var sidebarOpaque: NSColor
	{
		// Opaque navigation retains the same tint over the shell's themed backing.
		// The under-surface alone is also used by cards and cannot represent these layers.
		let backing = AppKitColorResolution.composite(
			(dark ? editor : surfaceUnder).withAlphaComponent(dark ? 0.8 : 0.85),
			over: surfaceUnder
		)
		return AppKitColorResolution.composite(
			sidebarTint,
			over: backing
		)
	}
	var control: NSColor
	{
		controlRGB.color(0.96)
	}
	var controlOpaque: NSColor
	{
		controlRGB.color()
	}
	var viewerControlSurface: NSColor
	{
		// Floating viewer controls retain the translucent Aqua surface; text editors
		// and other opaque controls continue to use controlOpaque.
		dark ? controlOpaque : control
	}
	var viewerControlHover: NSColor
	{
		AppKitColorResolution.composite(
			hoverOverlay,
			over: viewerControlSurface
		)
	}
	// Viewer selection uses the profile's information blue, independently of named chat accents.
	func viewerControlSelection(active: Bool) -> NSColor
	{
		AppKitColorResolution.composite(
			RGB(profile.accent).color(active ? 0.15 : 0.1),
			over: surface
		)
	}
	var viewerControlSelectedText: NSColor
	{
		dark ? informationText(RGB(profile.accent)).color() : accentText
	}
	var elevated: NSColor
	{
		elevatedRGB.color(0.96)
	}
	var elevatedOpaque: NSColor
	{
		elevatedRGB.color()
	}
	// Form cards keep their elevation independent of the window backing.
	var formCard: NSColor
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.025 + 0.035 * q : 0.08 + 0.08 * q
		).color()
	}
	var elevatedSecondary: NSColor
	{
		dark ? ink.color(0.02 + 0.02 * q) : background.mix(
			white,
			0.08 + 0.08 * q
		).color(0.96)
	}
	var elevatedSecondaryOpaque: NSColor
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.04 + 0.05 * q : 0.08 + 0.08 * q
		).color()
	}
	var editor: NSColor
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.07 : 0.12
		).color()
	}
	var panel: NSColor
	{
		background.mix(
			dark ? ink : white,
			dark ? 0.03 + 0.03 * q : 0.18 + 0.008 * q
		).color()
	}
	var foreground: NSColor
	{
		let fallback = dark && profile.background == 0x181818 && profile.foreground == 0xFFFFFF &&
			profile.accent == 0x339CFF && profile.namedAccent == nil && profile.contrast == 60 &&
			!profile.opaqueWindows && !profile.hasCustomFonts && profile.diffAdded == 0x40C977 &&
			profile.diffRemoved == 0xFA423E && profile.skill == 0xAD7BF9
		return fallback ? RGB(0xDFDFDF).color() : ink.color()
	}
	var secondaryText: NSColor
	{
		foreground.withAlphaComponent(0.65)
	}
	var chromeSecondaryText: NSColor
	{
		ink.color(0.65 + 0.1 * q)
	}
	var tertiaryText: NSColor
	{
		ink.color(dark ? 0.42 + 0.13 * q : 0.45 + 0.1 * q)
	}
	var primaryIcon: NSColor
	{
		ink.color(dark ? 0.82 + 0.14 * q : 1)
	}
	var secondaryIcon: NSColor
	{
		ink.color(0.65 + 0.1 * q)
	}
	var tertiaryIcon: NSColor
	{
		ink.color(0.45 + 0.1 * q)
	}
	var border: NSColor
	{
		ink.color(0.06 + 0.04 * q)
	}
	var heavyBorder: NSColor
	{
		ink.color((dark ? 0.12 : 0.09) + 0.06 * q)
	}
	var lightBorder: NSColor
	{
		ink.color((dark ? 0.03 : 0.04) + 0.02 * q)
	}
	var accent: NSColor
	{
		accentRGB.color()
	}
	var accentText: NSColor
	{
		namedText ?? accentTextRGB.color()
	}
	var inlineReferenceText: NSColor
	{
		AppKitColorResolution.composite(
			accentText.withAlphaComponent(0.8),
			over: foreground
		)
	}
	var focus: NSColor
	{
		profile.namedAccent == nil ? (dark ? accentTextRGB.color(0.7 + 0.1 * q) : accent) : accent
	}
	var accentBackground: NSColor
	{
		if let namedSurface
		{
			return namedSurface
		}
		return (dark ? black : background).mix(
			accentRGB,
			dark ? 0.20 + 0.08 * q : 0.11 + 0.04 * q
		).color()
	}
	var accentBackgroundHover: NSColor
	{
		if let namedSurface
		{
			return namedSurface
		}
		return (dark ? black : background).mix(
			accentRGB,
			dark ? 0.21 + 0.10 * q : 0.12 + 0.045 * q
		).color()
	}
	var accentBackgroundPressed: NSColor
	{
		if let namedSurface
		{
			return namedSurface
		}
		return (dark ? black : background).mix(
			accentRGB,
			dark ? 0.22 + 0.12 * q : 0.13 + 0.05 * q
		).color()
	}
	var hoverOverlay: NSColor
	{
		ink.color(dark ? 0.06 + 0.03 * q : 0.04 + 0.03 * q)
	}
	var controlHoverOpaque: NSColor
	{
		controlRGB.mix(
			ink,
			dark ? 0.06 + 0.03 * q : 0.04 + 0.03 * q
		).color()
	}
	var tooltipCapsule: NSColor
	{
		dark ? background.mix(
			ink,
			0.08 + q / 15
		).color() : foreground
	}
	var errorText: NSColor
	{
		RGB(profile.diffRemoved).mix(
			white,
			dark ? 0.2 : 0
		).color()
	}
	var selectedOverlay: NSColor
	{
		ink.color(0.08)
	}
	var diffAdded: NSColor
	{
		RGB(profile.diffAdded).color()
	}
	var diffRemoved: NSColor
	{
		RGB(profile.diffRemoved).color()
	}
	var skill: NSColor
	{
		RGB(profile.skill).color()
	}
	var applicationMenu: NSColor
	{
		background.mix(
			ink,
			0.02 + 0.02 * q
		).color()
	}
	var primaryButtonBackground: NSColor
	{
		dark ? background.mix(
			black,
			0.38 + 0.12 * q
		).color() : foreground
	}
	var primaryButtonHover: NSColor
	{
		ink.color(dark ? 0.04 + 0.03 * q : 0.05 + 0.06 * q)
	}
	var primaryButtonPressed: NSColor
	{
		ink.color(dark ? 0.07 + 0.05 * q : 0.10 + 0.12 * q)
	}
	var primaryButtonInactive: NSColor
	{
		ink.color(dark ? 0.02 + 0.02 * q : 0.18 + 0.14 * q)
	}
	var secondaryButtonBackground: NSColor
	{
		ink.color(0.04 + 0.02 * q)
	}
	var secondaryButtonHover: NSColor
	{
		ink.color(dark ? 0.06 + 0.03 * q : 0.04 + 0.03 * q)
	}
	var secondaryButtonPressed: NSColor
	{
		ink.color(dark ? 0.09 + 0.05 * q : 0.03 + 0.02 * q)
	}
	var secondaryButtonInactive: NSColor
	{
		ink.color(dark ? 0.02 + 0.03 * q : 0.01 + 0.02 * q)
	}
	var tertiaryButtonBackground: NSColor
	{
		ink.color(dark ? 0.02 + 0.015 * q : 0)
	}
	var tertiaryButtonHover: NSColor
	{
		ink.color(dark ? 0.05 + 0.03 * q : 0.08 + 0.04 * q)
	}
	var tertiaryButtonPressed: NSColor
	{
		ink.color(dark ? 0.07 + 0.05 * q : 0.16 + 0.08 * q)
	}
	var primaryButtonText: NSColor
	{
		dark ? background.mix(
			black,
			0.38 + 0.12 * q
		).color() : surface
	}
	var secondaryButtonText: NSColor
	{
		dark ? ink.mix(
			background,
			0.70 + 0.10 * q
		).color() : foreground
	}
	var tertiaryButtonText: NSColor
	{
		ink.color(0.45 + 0.10 * q)
	}
	var messageBackground: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return foreground.withAlphaComponent(0.05)
		}
		if name == .black && !dark
		{
			return black.color()
		}
		if name == .default || name == .black || !profile.colorizeMessages
		{
			return RGB(dark ? 0x323232 : 0xE9E9E9).color(dark ? 0.85 : 0.5)
		}
		return RGB(namedColors(name)[dark ? 7 : 1]).color()
	}
	var messageText: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return foreground
		}
		if name == .black && !dark
		{
			return white.color()
		}
		if name == .default || name == .black || !profile.colorizeMessages
		{
			return RGB(dark ? 0xFFFFFF : 0x0D0D0D).color()
		}
		return RGB(namedColors(name)[dark ? 0 : 9]).color()
	}
	var selectionBackground: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return accentTextRGB.color(0.3)
		}
		if name == .black
		{
			return dark ? ink.exactAlphaColor(0.32) : RGB(0xAFAFAF).exactAlphaColor(89.0 / 255)
		}
		let colors = namedColors(name)
		if name == .default
		{
			return RGB(colors[dark ? 2 : 3]).exactAlphaColor(dark ? 0.4 : 89.0 / 255)
		}
		return RGB(colors[dark ? 4 : 3])
			.exactAlphaColor(dark ? (name == .yellow ? 128.0 / 255 : 0.6) : 89.0 / 255)
	}
	var inlineCode: NSColor
	{
		ink.exactAlphaColor(dark ? 0.09 : 0.0929412)
	}
	var unreadBadgeText: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return onAccent
		}
		return name == .yellow ? RGB(0x0D0D0D).color() : white.color()
	}
	var composerFill: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return foreground
		}
		if name == .default || name == .black
		{
			return (dark ? white : black).color()
		}
		return RGB(namedColors(name)[dark && name != .pink ? 5 : 4]).color()
	}
	var composerText: NSColor
	{
		guard let name = profile.namedAccent
		else
		{
			return controlOpaque
		}
		return (dark && (name == .default || name == .black) ? black : white).color()
	}
	var onAccent: NSColor
	{
		let c = accentRGB
		func linear(_ channel: Double) -> Double
		{
			let v = channel / 255
			return v <= 0.04045 ? v / 12.92 : pow(
				(v + 0.055) / 1.055,
				2.4
			)
		}
		let luminance = linear(c.red) * 0.2126 + linear(c.green) * 0.7152 + linear(c.blue) * 0.0722
		let delta = c.blue - min(
			c.red,
			c.green
		)
		let isBlue = c.blue > c.red && c.blue > c.green && delta > 0
		let hue = isBlue ? ((c.red - c.green) / delta + 4) * 60 : 0
		let saturation = isBlue ? delta / c.blue : 0
		let forceWhite = isBlue &&
			((saturation >= 0.8 && (205 ... 212).contains(hue)) ||
				(saturation >= 0.6 && (218 ... 233).contains(hue) && luminance <= 0.21))
		return (forceWhite || luminance <= 0.179 ? white : black).color()
	}
	var warningText: NSColor
	{
		// Status warning ink is independent of the selectable orange accent ramp.
		RGB(dark ? 0xFF8549 : namedColors(.orange)[6]).color()
	}
	var avatarText: NSColor
	{
		contrastInk(on: accentBackground)
	}
	var tooltipText: NSColor
	{
		dark ? foreground : surface
	}
	var descriptionText: NSColor
	{
		foreground.withAlphaComponent(0.7)
	}
	// Diagram nodes use contrast ink rather than a canvas-text border.
	var diagramOutline: NSColor
	{
		contrastInk(on: surface).withAlphaComponent(0.1)
	}
	func switchThumb(on: Bool) -> NSColor
	{
		// A switch thumb is a non-text affordance: prefer light ink down to 3:1,
		// while retaining dark ink for bright custom accents.
		contrastInk(
			on: on ? accent : surface,
			lightInkThreshold: on ? 0.3 : 0.179
		)
	}
	// Overlay text is paired with the deliberately dark image scrim, independently of
	// custom canvas colors.
	var overlayText: NSColor
	{
		white.color()
	}
	func scrim(opacity: CGFloat) -> NSColor
	{
		black.color(Double(opacity))
	}

	func imageBackdrop(opacity: CGFloat) -> NSColor
	{
		// Image artwork needs a light neutral veil in Aqua and a dark veil in Dark Aqua;
		// the generic black scrim cannot preserve that appearance-dependent contrast pair.
		(dark ? black : RGB(0xE3E3E3)).color(Double(opacity))
	}

	private func contrastInk(
		on color: NSColor,
		lightInkThreshold: CGFloat = 0.179
	) -> NSColor
	{
		let c = color.usingColorSpace(.sRGB)!
		func linear(_ x: CGFloat) -> CGFloat
		{
			x <= 0.04045 ? x / 12.92 : pow(
				(x + 0.055) / 1.055,
				2.4
			)
		}
		let luminance = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) +
			0.0722 * linear(c.blueComponent)
		return luminance > lightInkThreshold ? black.color() : white.color()
	}

	func diffBackground(
		added: Bool,
		gutter: Bool
	) -> NSColor
	{
		AppKitColorResolution.labMix(
			gutter ? surfaceUnder : surface,
			added ? diffAdded : diffRemoved,
			amount: gutter ? (dark ? 0.15 : 0.09) : (dark ? 0.20 : 0.12)
		)
	}
	func diffSelection(
		over color: NSColor,
		gutter: Bool
	) -> NSColor
	{
		AppKitColorResolution.labMix(
			color,
			accentText,
			amount: gutter ? (dark ? 0.4 : 0.25) : (dark ? 0.25 : 0.18)
		)
	}

	var qrSurface: NSColor
	{
		surface
	}
	var qrInk: NSColor
	{
		contrastInk(on: qrSurface)
	}

	var fullscreenQRSurface: NSColor
	{
		controlOpaque
	}
	var fullscreenQRInk: NSColor
	{
		contrastInk(on: fullscreenQRSurface)
	}

}
