import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsAppearanceColorTests
{
	@Test func modeArtworkKeepsItsNeutralStageWhileSemanticAccentChanges() throws
	{
		for dark in [false, true]
		{
			for accent in [NSColor.red, .blue]
			{
				let context = try #require(CGContext(
					data: nil,
					width: 80,
					height: 60,
					bitsPerComponent: 8,
					bytesPerRow: 80 * 4,
					space: CGColorSpace(name: CGColorSpace.sRGB)!,
					bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
				))
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current = NSGraphicsContext(
					cgContext: context,
					flipped: false
				)
				SettingsAppearanceModeArtwork.draw(
					dark: dark,
					accent: accent,
					in: NSRect(
						x: 0,
						y: 0,
						width: 80,
						height: 60
					)
				)
				NSGraphicsContext.restoreGraphicsState()
				let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
				let offset = (2 * 80 + 40) * 4
				let stage = dark ? 38 : 244
				// The context's encoded bytes are sRGB. NSBitmapImageRep.colorAt returns a
				// calibrated color that would apply a second profile conversion on readback.
				#expect(Int(pixels[offset]) == stage)
				#expect(Int(pixels[offset + 1]) == stage)
				#expect(Int(pixels[offset + 2]) == stage)
				#expect(pixels[offset + 3] == 255)
				let hasAccent = stride(
					from: 0,
					to: 80 * 60 * 4,
					by: 4
				).contains
				{
					index in
					accent == .red
						? pixels[index] > 200 && pixels[index + 2] < 20
						: pixels[index + 2] > 200 && pixels[index] < 20
				}
				#expect(hasAccent)
			}
		}
	}

	@Test func compactNumberFieldsIncrementTheEditingDraftAndClampToTheirOwnRange() throws
	{
		let name = "AppearanceNumberInput.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		let preferences = TypographyPreferences(defaults: defaults)
		let page = SettingsAppearancePage(
			preferences: preferences,
			colorPreferences: ColorPreferences(defaults: defaults),
			center: NotificationCenter()
		)
		let editor = NSTextView()
		#expect(page.uiSizeField.fittingSize == NSSize(
			width: 64,
			height: 28
		))
		#expect(page.modePicker.fittingSize == NSSize(
			width: 272,
			height: 60
		))
		editor.string = "12"
		#expect(page.control(
			page.uiSizeField,
			textView: editor,
			doCommandBy: #selector(NSResponder.moveUp(_:))
		))
		#expect(preferences.configuration.uiSize == 13)
		editor.string = "16"
		#expect(page.control(
			page.uiSizeField,
			textView: editor,
			doCommandBy: #selector(NSResponder.moveUp(_:))
		))
		#expect(preferences.configuration.uiSize == 16)
		editor.string = "8"
		#expect(page.control(
			page.codeSizeField,
			textView: editor,
			doCommandBy: #selector(NSResponder.moveDown(_:))
		))
		#expect(preferences.configuration.codeSize == 8)
		#expect(preferences.configuration.contentSize == 15)
	}

	@Test func selectingColorThemeAppliesOnlyTheCurrentMode() throws
	{
		let name = "SettingsAppearanceColorTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		let colors = ColorPreferences(defaults: defaults)
		let page = SettingsAppearancePage(
			preferences: TypographyPreferences(defaults: defaults),
			colorPreferences: colors,
			center: NotificationCenter()
		)
		let light = colors.configuration.light
		#expect(page.modePicker.buttons[2].dispatchConfiguredAction())
		#expect(page.modePicker.selectedMode == .dark)
		let preset = try #require(ColorThemePresets.preset(
			id: "ayu",
			appearance: .dark
		))
		page.presetPicker.onSelect?(preset.id)
		#expect(colors.configuration.dark.background == preset.profile.background)
		#expect(colors.configuration.dark.presetID == preset.id)
		#expect(colors.configuration.dark.codeThemeID == preset.codeTheme)
		#expect(colors.configuration.light == light)
		#expect(page.modePicker.buttons.map(\.state) == [.off, .off, .on])
		page.modePicker.update(configuration: ColorThemeConfiguration(
			light: light,
			dark: colors.configuration.dark,
			mode: .system
		))
		#expect(page.modePicker.buttons.map(\.state) == [.on, .off, .off])
		#expect(colors.configuration.mode == .dark)
		let matrix = try #require(ColorThemePresets.preset(
			id: "matrix",
			appearance: .dark
		))
		#expect(matrix.profile.opaqueWindows)
		page.presetPicker.onSelect?(matrix.id)
		#expect(colors.configuration.dark.opaqueWindows == matrix.profile.opaqueWindows)
		#expect(colors.configuration.dark.hasCustomFonts)
		#expect(colors.configuration.light == light)
		let dark = colors.configuration.dark
		#expect(page.modePicker.buttons[1].dispatchConfiguredAction())
		#expect(page.modePicker.selectedMode == .light)
		#expect(page.presetPicker.selectedID == (light.presetID ?? "custom"))
		#expect(colors.configuration.dark == dark)
	}

	@Test func changingColorsPreservesOtherAppearanceProfiles() throws
	{
		let name = "SettingsAppearanceColorTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		let colors = ColorPreferences(defaults: defaults)
		let original = colors.configuration
		let dark = original.dark
		colors.save(
			ColorThemeConfiguration(
				light: original.light,
				dark: ColorThemeProfile(
					background: dark.background,
					foreground: dark.foreground,
					accent: dark.accent,
					contrast: dark.contrast,
					diffAdded: dark.diffAdded,
					diffRemoved: dark.diffRemoved,
					skill: dark.skill,
					colorizeMessages: false,
					presetID: "fixture",
					codeThemeID: "fixture-dark",
					opaqueWindows: true,
					hasCustomFonts: true
				),
				mode: .system
			),
			center: NotificationCenter()
		)
		let page = SettingsAppearancePage(
			preferences: TypographyPreferences(defaults: defaults),
			colorPreferences: colors,
			center: NotificationCenter()
		)
		let initialLight = colors.configuration.light
		#expect(page.modePicker.buttons[2].dispatchConfiguredAction())
		#expect(page.modePicker.selectedMode == .dark)
		page.backgroundField.stringValue = "#203040"
		let colorAction = try #require(page.backgroundField.action)
		#expect(page.backgroundField.sendAction(
			colorAction,
			to: page.backgroundField.target
		))
		#expect(colors.configuration.dark.background == 0x203040)
		#expect(colors.configuration.light == initialLight)
		page.accentPicker.onSelect?(ColorNamedAccent.green.rawValue)
		#expect(colors.configuration.dark.namedAccent == .green)
		let expectedAccent = ColorPalette(
			configuration: colors.configuration.dark,
			mode: .dark
		)
		.accent
		#expect(page.contrastSlider.trackFillColor?.usingColorSpace(.sRGB) == expectedAccent
			.usingColorSpace(.sRGB))
		page.contrastSlider.integerValue = 73
		let contrastAction = try #require(page.contrastSlider.action)
		#expect(page.contrastSlider.sendAction(
			contrastAction,
			to: page.contrastSlider.target
		))
		#expect(colors.configuration.dark.namedAccent == .green)
		#expect(colors.configuration.dark.contrast == 73)
		#expect(colors.configuration.dark.presetID == "fixture")
		#expect(colors.configuration.dark.codeThemeID == "fixture-dark")
		#expect(colors.configuration.dark.opaqueWindows)
		#expect(colors.configuration.dark.hasCustomFonts)
		#expect(!colors.configuration.dark.colorizeMessages)
		#expect(page.translucentSidebarSwitch.state == .off)
		page.translucentSidebarSwitch.state = .on
		let translucentAction = try #require(page.translucentSidebarSwitch.action)
		#expect(page.translucentSidebarSwitch.sendAction(
			translucentAction,
			to: page.translucentSidebarSwitch.target
		))
		#expect(!colors.configuration.dark.opaqueWindows)
		#expect(colors.configuration.light == initialLight)
		page.backgroundField.stringValue = "#12ZZZZ"
		#expect(page.backgroundField.sendAction(
			colorAction,
			to: page.backgroundField.target
		))
		#expect(colors.configuration.dark.background == 0x203040)
		page.accentField.stringValue = "#EA4372"
		let customAction = try #require(page.accentField.action)
		#expect(page.accentField.sendAction(
			customAction,
			to: page.accentField.target
		))
		#expect(colors.configuration.dark.accent == 0xEA4372)
		#expect(colors.configuration.dark.namedAccent == nil)
		#expect(colors.configuration.light == initialLight)
		let savedDark = colors.configuration.dark
		#expect(page.modePicker.buttons[1].dispatchConfiguredAction())
		#expect(page.modePicker.selectedMode == .light)
		page.foregroundField.stringValue = "#112233"
		let foregroundAction = try #require(page.foregroundField.action)
		#expect(page.foregroundField.sendAction(
			foregroundAction,
			to: page.foregroundField.target
		))
		#expect(colors.configuration.light.foreground == 0x112233)
		#expect(colors.configuration.dark == savedDark)
		page.translucentSidebarSwitch.state = .off
		#expect(page.translucentSidebarSwitch.sendAction(
			translucentAction,
			to: page.translucentSidebarSwitch.target
		))
		#expect(colors.configuration.light.opaqueWindows)
		#expect(colors.configuration.dark == savedDark)
	}
}
