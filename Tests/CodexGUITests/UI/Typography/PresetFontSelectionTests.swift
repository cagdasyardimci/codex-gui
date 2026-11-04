import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct PresetFontSelectionTests
{
	@Test func typographyBindingDoesNotRetainItsView()
	{
		weak var retained: NSTextField?
		autoreleasepool
		{
			let field = NSTextField(labelWithString: "Label")
			field.setTypographyRole(TypographyTokens.Role(size: 14))
			retained = field
		}
		#expect(retained == nil)
	}
	@Test func presetFamiliesFollowAppearanceAndRetainSizeAndWeight() throws
	{
		let matrix = try #require(ColorThemePresets.preset(
			id: "matrix",
			appearance: .dark
		))
		let config = ColorThemeConfiguration(
			light: .light,
			dark: matrix.profile,
			mode: .system
		)
		let dark = try #require(NSAppearance(named: .darkAqua))
		let light = try #require(NSAppearance(named: .aqua))
		let role = TypographyTokens.Role(
			rule: .ui(offset: 0),
			selection: .interface(weight: .strong)
		)
		let typography = TypographyConfiguration(
			uiSize: 16,
			codeSize: 12
		)
		let darkFont = AppKitFontResolver.font(
			role,
			configuration: typography,
			appearance: dark,
			colorConfiguration: config
		)
		let lightFont = AppKitFontResolver.font(
			role,
			configuration: typography,
			appearance: light,
			colorConfiguration: config
		)
		#expect(darkFont.familyName == "Menlo")
		#expect(darkFont.pointSize == 16)
		#expect(lightFont.familyName != "Menlo")
	}

	@Test func familyListsRespectOrderAndGenericFallback()
	{
		#expect(AppKitFontResolver
			.firstAvailableFamily(in: "No Such Family, 'Arial', monospace") == "Arial")
		#expect(AppKitFontResolver
			.firstAvailableFamily(in: "No Such Family, ui-monospace") == "Menlo")
		#expect(AppKitFontResolver.firstAvailableFamily(in: "No Such Family, sans-serif") == nil)
	}

	@Test func explicitFamilyRolesRemainIndependentOfPreset() throws
	{
		let matrix = try #require(ColorThemePresets.preset(
			id: "matrix",
			appearance: .dark
		))
		let config = ColorThemeConfiguration(
			dark: matrix.profile,
			mode: .dark
		)
		let font = AppKitFontResolver.font(
			TypographyTokens.Role(
				size: 14,
				selection: .family(
					"Arial",
					weight: .regular
				)
			),
			colorConfiguration: config
		)
		#expect(font.familyName == "Arial")
	}

	@Test func contentUsesPresetContentFamily() throws
	{
		let preset = try #require(ColorThemePresets.preset(
			id: "og",
			appearance: .dark
		))
		let configuration = ColorThemeConfiguration(
			dark: preset.profile,
			mode: .dark
		)
		let font = AppKitFontResolver.font(
			TypographyTokens.Role(size: 14),
			colorConfiguration: configuration,
			scope: .content
		)
		#expect(font.familyName == "Arial")
	}

	@Test func codeUsesThePresetCodeFallbackList() throws
	{
		let preset = try #require(ColorThemePresets.preset(
			id: "vercel",
			appearance: .light
		))
		let list = try #require(preset.codeFontFamily)
		let family = try #require(AppKitFontResolver.firstAvailableFamily(in: list))
		let configuration = ColorThemeConfiguration(
			light: preset.profile,
			mode: .light
		)
		let font = AppKitFontResolver.font(
			TypographyTokens.Role(
				rule: .code,
				selection: .code(weight: .regular)
			),
			colorConfiguration: configuration
		)
		let expected = AppKitFontResolver.familyFont(
			family,
			size: TypographyConfiguration.current.codeSize,
			weight: .regular
		)
		#expect(font.fontName == expected.fontName)
	}
}
