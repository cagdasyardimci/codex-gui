import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ColorPaletteTests
{
	@Test func viewerSelectionUsesInformationBlueAndCanvasAcrossNamedChatAccents() throws
	{
		for chatAccent: ColorNamedAccent? in [nil, .pink]
		{
			let palette = ColorPalette(
				configuration: ColorThemeProfile(
					background: 0x111111,
					foreground: 0xFCFCFC,
					accent: 0x0169CC,
					contrast: 60,
					namedAccent: chatAccent
				),
				mode: .dark
			)
			for (active, expected) in [(false, [15.4, 25.8, 35.7]), (true, [14.6, 30.2, 45.05])]
			{
				let color = try #require(palette.viewerControlSelection(active: active)
					.usingColorSpace(.sRGB))
				for (component, expected) in zip(
					[color.redComponent, color.greenComponent, color.blueComponent],
					expected
				)
				{
					#expect(abs(component * 255 - expected) < 0.001)
				}
				#expect(color.alphaComponent == 1)
			}
			expectColor(
				palette.viewerControlSelectedText,
				0x64A4E0
			)
		}
	}
	@Test func inlineReferenceInkBlendsThemeInfoAndPrimaryTextInSRGB() throws
	{
		let samples: [(ColorAppearance, ColorThemeProfile, [CGFloat])] = [
			(.light, .light, [3.4, 86.6, 165.8]),
			(.dark, ColorThemeProfile(
				background: 0x111111,
				foreground: 0xFCFCFC,
				accent: 0x0169CC,
				contrast: 60
			), [130.4, 181.6, 229.6]),
		]
		for (appearance, profile, expected) in samples
		{
			let palette = ColorPalette(
				configuration: profile,
				mode: appearance
			)
			let ink = try #require(palette.inlineReferenceText.usingColorSpace(.sRGB))
			let actual = [ink.redComponent, ink.greenComponent, ink.blueComponent]
			for (component, expected) in zip(
				actual,
				expected
			)
			{
				#expect(abs(component * 255 - expected) < 0.001)
			}
			#expect(ink.alphaComponent == 1)
			#expect(ink != palette.accentText.usingColorSpace(.sRGB))
		}
	}

	@Test func opaqueSidebarRetainsItsCompositedSurfaceAndFollowsThemeInputs() throws
	{
		let dark = ColorPalette(
			configuration: ColorThemeProfile(
				background: 0x111111,
				foreground: 0xFCFCFC,
				accent: 0x0169CC,
				contrast: 60
			),
			mode: .dark
		)
		let light = ColorPalette(
			configuration: .light,
			mode: .light
		)
		let darkColor = try #require(dark.sidebarOpaque.usingColorSpace(.sRGB))
		let lightColor = try #require(light.sidebarOpaque.usingColorSpace(.sRGB))
		#expect((darkColor.redComponent * 255).rounded() == 21)
		#expect((lightColor.redComponent * 255).rounded() == 252)
		#expect(dark.sidebarOpaque.alphaComponent == 1)
		#expect(light.sidebarOpaque.alphaComponent == 1)
		#expect(dark.sidebarOpaque != dark.surfaceUnder)
		let custom = ColorPalette(
			configuration: ColorThemeProfile(
				background: 0x203040,
				foreground: 0xE0F0FF,
				accent: 0xEF1234,
				contrast: 80
			),
			mode: .dark
		)
		#expect(custom.sidebarOpaque != dark.sidebarOpaque)
		#expect(custom.sidebarOpaque.alphaComponent == 1)
	}
	@Test(arguments: [ColorAppearance.light, .dark])
	func contrastContextsRetainProfileColorsAndOpaqueQRSurfaces(_ appearance: ColorAppearance)
	{
		let profile = ColorThemeProfile(
			background: 0x142536,
			foreground: 0xE5D4C3,
			accent: 0x0077CC,
			contrast: 60
		)
		let palette = ColorPalette(
			configuration: profile,
			mode: appearance
		)
		expectColor(
			palette.tooltipText,
			appearance == .dark ? profile.foreground : profile.background
		)
		expectColor(
			palette.descriptionText,
			profile.foreground
		)
		#expect(palette.descriptionText.alphaComponent == 0.7)
		#expect(palette.qrSurface == palette.surface)
		#expect(palette.fullscreenQRSurface == palette.controlOpaque)
		#expect(palette.qrSurface.alphaComponent == 1)
		#expect(palette.fullscreenQRSurface.alphaComponent == 1)
		#expect(palette.qrInk != palette.qrSurface)
	}

	@Test func derivedControlAndErrorColorsFollowThemeInputs()
	{
		let original = ColorPalette(
			configuration: .dark,
			mode: .dark
		)
		let changed = ColorPalette(
			configuration: ColorThemeProfile(
				background: 0x102030,
				foreground: 0xE0E8F0,
				accent: 0x336699,
				contrast: 60,
				diffRemoved: 0xD04050
			),
			mode: .dark
		)
		#expect(original.controlHoverOpaque.alphaComponent == 1)
		#expect(changed.controlHoverOpaque.alphaComponent == 1)
		#expect(original.controlHoverOpaque != changed.controlHoverOpaque)
		#expect(original.tooltipCapsule != changed.tooltipCapsule)
		#expect(original.errorText != changed.errorText)
	}
	@Test func measuredDarkPaletteAndContrast()
	{
		let profile = ColorThemeProfile(
			background: 0x111827,
			foreground: 0xE4E4E7,
			accent: 0xFF5C5C,
			contrast: 60
		)
		let palette = ColorPalette(
			configuration: profile,
			mode: .dark
		)
		expectColor(
			palette.surfaceUnder,
			0x0E1421
		)
		expectColor(
			palette.controlOpaque,
			0x242A38
		)
		expectColor(
			palette.elevatedOpaque,
			0x2C3240
		)
		expectColor(
			palette.accentText,
			0xFF9C9C
		)
		expectColor(
			palette.accentBackground,
			0x3F1717
		)
		#expect(abs(palette.border.alphaComponent - 0.084) < 0.00001)
		#expect(abs(palette.secondaryText.alphaComponent - 0.65) < 0.00001)
		#expect(abs(palette.chromeSecondaryText.alphaComponent - 0.71) < 0.00001)
	}

	@Test func namedAccentOverridesCustomColors()
	{
		let profile = ColorThemeProfile(
			background: 0x111111,
			foreground: 0xFCFCFC,
			accent: 0xE040A0,
			contrast: 60,
			namedAccent: .blue
		)
		let palette = ColorPalette(
			configuration: profile,
			mode: .dark
		)
		expectColor(
			palette.accent,
			0x3A83F7
		)
		expectColor(
			palette.accentText,
			0x2C67C5
		)
		expectColor(
			palette.accentBackground,
			0x133463
		)
		expectColor(
			palette.messageBackground,
			0x173E76
		)
		expectColor(
			palette.composerFill,
			0x2C67C5
		)
		expectColor(
			palette.unreadBadgeText,
			0xFFFFFF
		)
		#expect(abs(palette.selectionBackground.alphaComponent - 0.6) < 0.00001)
	}

	@Test func onAccentUsesMeasuredLuminanceAndBlueExceptions()
	{
		func color(_ accent: UInt32) -> NSColor
		{
			let profile = ColorThemeProfile(
				background: 0x111111,
				foreground: 0xFCFCFC,
				accent: accent,
				contrast: 60
			)
			return ColorPalette(
				configuration: profile,
				mode: .dark
			).onAccent
		}
		expectColor(
			color(0x757575),
			0xFFFFFF
		)
		expectColor(
			color(0x767676),
			0x000000
		)
		expectColor(
			color(0x0088FF),
			0xFFFFFF
		)
		expectColor(
			color(0x00FFFF),
			0x000000
		)
	}

	@Test func fallbackForegroundRequiresEntireReferenceProfile()
	{
		let fallback = ColorThemeProfile(
			background: 0x181818,
			foreground: 0xFFFFFF,
			accent: 0x339CFF,
			contrast: 60,
			diffAdded: 0x40C977,
			diffRemoved: 0xFA423E,
			skill: 0xAD7BF9
		)
		let customFont = ColorThemeProfile(
			background: 0x181818,
			foreground: 0xFFFFFF,
			accent: 0x339CFF,
			contrast: 60,
			diffAdded: 0x40C977,
			diffRemoved: 0xFA423E,
			skill: 0xAD7BF9,
			hasCustomFonts: true
		)
		let opaque = ColorThemeProfile(
			background: 0x181818,
			foreground: 0xFFFFFF,
			accent: 0x339CFF,
			contrast: 60,
			diffAdded: 0x40C977,
			diffRemoved: 0xFA423E,
			skill: 0xAD7BF9,
			opaqueWindows: true
		)
		expectColor(
			ColorPalette(
				configuration: fallback,
				mode: .dark
			).foreground,
			0xDFDFDF
		)
		expectColor(
			ColorPalette(
				configuration: fallback,
				mode: .dark
			).secondaryText,
			0xDFDFDF
		)
		expectColor(
			ColorPalette(
				configuration: customFont,
				mode: .dark
			).foreground,
			0xFFFFFF
		)
		expectColor(
			ColorPalette(
				configuration: opaque,
				mode: .dark
			).foreground,
			0xFFFFFF
		)
	}

	@Test func preferencesPersistProfilesIndependently()
	{
		let suite = "ColorPaletteTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let preferences = ColorPreferences(defaults: defaults)
		let profile = ColorThemeProfile(
			background: 0x203040,
			foreground: 0xF0E0C0,
			accent: 0x00AACC,
			contrast: 35,
			namedAccent: .green,
			colorizeMessages: false
		)
		let configuration = ColorThemeConfiguration(
			light: .light,
			dark: profile,
			mode: .dark
		)
		preferences.save(
			configuration,
			center: NotificationCenter()
		)
		#expect(preferences.configuration == configuration)
	}

	@Test func contentColorsFollowTheMeasuredOKLabAdjustment()
	{
		let profile = ColorThemeProfile(
			background: 0x111111,
			foreground: 0xC0E0FF,
			accent: 0x3A83F7,
			contrast: 60
		)
		let palette = ColorPalette(
			configuration: profile,
			mode: .dark
		)
		let content = ColorContentPalette(
			surfaceUnder: palette.surfaceUnder,
			foreground: profile.foreground,
			mode: .dark
		)
		let blue = content.adapt(0x81A6F9)
		#expect(abs(blue.lightness - 0.724245) < 0.0001)
		#expect(abs(blue.a - -0.010726) < 0.0001)
		#expect(abs(blue.b - -0.126112) < 0.0001)
		let standard = ColorContentPalette(
			surfaceUnder: NSColor(
				srgbRed: 14.0 / 255,
				green: 14.0 / 255,
				blue: 14.0 / 255,
				alpha: 1
			),
			foreground: 0xFCFCFC,
			mode: .dark
		)
		#expect(standard.adapt(0x81A6F9) == ColorContentPalette.Lab(hex: 0x81A6F9))
	}

	private func expectColor(
		_ color: NSColor,
		_ hex: UInt32
	)
	{
		let rgb = color.usingColorSpace(.sRGB)!
		#expect(abs(rgb.redComponent - CGFloat((hex >> 16) & 255) / 255) < 0.00001)
		#expect(abs(rgb.greenComponent - CGFloat((hex >> 8) & 255) / 255) < 0.00001)
		#expect(abs(rgb.blueComponent - CGFloat(hex & 255) / 255) < 0.00001)
	}
}
