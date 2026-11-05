import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsAppearanceFontTests
{
	@Test func fontChoicesPersistPerAppearanceAndSurviveOtherEdits() throws
	{
		let name = "SettingsAppearanceFontTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		let colors = ColorPreferences(defaults: defaults)
		let typography = TypographyPreferences(defaults: defaults)
		let page = SettingsAppearancePage(
			preferences: typography,
			colorPreferences: colors,
			center: NotificationCenter()
		)
		#expect(page.contentFontPicker.title == "Same as UI font")
		#expect(page.modePicker.buttons[2].dispatchConfiguredAction())
		page.uiFontPicker.onSelect?("Arial")
		page.contentFontPicker.onSelect?("Times New Roman")
		page.codeFontPicker.onSelect?("Courier")
		#expect(page.uiFontPicker.selectedID == "Arial")
		page.backgroundField.stringValue = "#203040"
		#expect(page.backgroundField.sendAction(
			page.backgroundField.action,
			to: page.backgroundField.target
		))
		page.codeSizeField.integerValue = 18
		#expect(page.codeSizeField.sendAction(
			page.codeSizeField.action,
			to: page.codeSizeField.target
		))
		let saved = ColorPreferences(defaults: defaults).configuration.dark
		#expect(saved.uiFontFamily == "Arial")
		#expect(saved.contentFontFamily == "Times New Roman")
		#expect(saved.codeFontFamily == "Courier")
		#expect(saved.background == 0x203040)
		#expect(typography.configuration.codeSize == 18)
		#expect(page.modePicker.buttons[1].dispatchConfiguredAction())
		#expect(page.uiFontPicker.selectedID == "")
		page.uiFontPicker.onSelect?("Verdana")
		#expect(page.modePicker.buttons[2].dispatchConfiguredAction())
		#expect(page.uiFontPicker.selectedID == "Arial")
		#expect(colors.configuration.light.uiFontFamily == "Verdana")
		page.uiFontPicker.onSelect?("")
		#expect(colors.configuration.dark.uiFontFamily == nil)
		#expect(colors.configuration.dark.contentFontFamily == "Times New Roman")
		page.presetPicker.onSelect?("matrix")
		#expect(colors.configuration.dark.contentFontFamily == nil)
		#expect(colors.configuration.dark.codeFontFamily == nil)
		#expect(page.codeFontPicker.selectedID == "")
		#expect(colors.configuration.light.uiFontFamily == "Verdana")
	}

	@Test func explicitFamiliesOverridePresetScopesWhileKeepingSizeAndSemanticWeight() throws
	{
		let profile = ColorThemeProfile(
			background: 0x111111,
			foreground: 0xFCFCFC,
			accent: 0x0169CC,
			contrast: 60,
			presetID: "matrix",
			uiFontFamily: "Arial",
			contentFontFamily: "Times New Roman",
			codeFontFamily: "Courier"
		)
		let colors = ColorThemeConfiguration(
			dark: profile,
			mode: .dark
		)
		let sizes = TypographyConfiguration(
			uiSize: 16,
			contentSize: 22,
			codeSize: 18
		)
		let role = TypographyTokens.Role(
			rule: .ui(offset: 0),
			selection: .interface(weight: .strong)
		)
		let ui = AppKitFontResolver.font(
			role,
			configuration: sizes,
			colorConfiguration: colors
		)
		#expect(ui.familyName == "Arial")
		#expect(ui.pointSize == 16)
		#expect(NSFontManager.shared.traits(of: ui).contains(.boldFontMask))
		let content = AppKitFontResolver.font(
			role,
			configuration: sizes,
			colorConfiguration: colors,
			scope: .content
		)
		#expect(content.familyName == "Times New Roman")
		let code = AppKitFontResolver.font(
			TypographyTokens.Role(
				rule: .code,
				selection: .code(weight: .regular)
			),
			configuration: sizes,
			colorConfiguration: colors
		)
		#expect(code.familyName == "Courier")
		#expect(code.pointSize == 18)
		let terminal = AppKitFontResolver.font(
			TypographyTokens.Terminal.text,
			configuration: sizes,
			colorConfiguration: colors
		)
		let terminalBold = AppKitFontResolver.font(
			TypographyTokens.Terminal.output(emphasized: true),
			configuration: sizes,
			colorConfiguration: colors
		)
		#expect(terminal.familyName == "Courier")
		#expect(terminal.pointSize == 15)
		#expect(terminalBold.familyName == "Courier")
		#expect(terminalBold.pointSize == 15)
		#expect(NSFontManager.shared.traits(of: terminalBold).contains(.boldFontMask))
		let artwork = AppKitFontResolver.font(
			TypographyTokens.Role(
				size: 14,
				selection: .family(
					"Menlo",
					weight: .regular
				)
			),
			colorConfiguration: colors
		)
		#expect(artwork.familyName == "Menlo")
		let inheritedContent = ColorThemeConfiguration(
			dark: ColorThemeProfile(
				background: profile.background,
				foreground: profile.foreground,
				accent: profile.accent,
				contrast: profile.contrast,
				presetID: "matrix",
				uiFontFamily: "Arial"
			),
			mode: .dark
		)
		#expect(AppKitFontResolver.font(
			role,
			colorConfiguration: inheritedContent,
			scope: .content
		).familyName == "Arial")
	}

	@Test func olderProfilesDecodeWithInheritedFonts() throws
	{
		let legacy = Data(
			#"{"background":16777215,"foreground":855309,"accent":92620,"contrast":45}"#
				.utf8
		)
		let profile = try JSONDecoder().decode(
			ColorThemeProfile.self,
			from: legacy
		)
		#expect(profile.uiFontFamily == nil)
		#expect(profile.contentFontFamily == nil)
		#expect(profile.codeFontFamily == nil)
		#expect(profile.background == ColorThemeProfile.light.background)
		#expect(profile.contrast == ColorThemeProfile.light.contrast)
	}
}
