import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct TypographyInvalidationTests
{
	@Test func colorOnlySavesPreserveFontBindingsWhileFontInputsStillRefresh() throws
	{
		let suite = "TypographyInvalidationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let preferences = ColorPreferences(defaults: defaults)
		let center = NotificationCenter()
		var applications = 0
		var colorRefreshes = 0
		var size = TypographyConfiguration.standard
		let field = NSTextField(labelWithString: "Retained content")
		field.setTypographyRole(
			TypographyTokens.Text.body,
			configuration:
			{
				size
			},
			center: center,
			onUpdate:
			{
				applications += 1
			}
		)
		let colorConsumer = TypographyObservation(center: center)
		{
			colorRefreshes += 1
		}
		func save(
			_ light: ColorThemeProfile,
			mode: ColorThemeMode = .system
		)
		{
			preferences.save(
				ColorThemeConfiguration(
					light: light,
					mode: mode
				),
				center: center
			)
		}
		func profile(
			ui: String? = nil,
			content: String? = nil,
			code: String? = nil,
			preset: String? = nil
		) -> ColorThemeProfile
		{
			ColorThemeProfile(
				background: 0xFFFFFF,
				foreground: 0x0D0D0D,
				accent: 0x0169CC,
				contrast: 65,
				presetID: preset,
				uiFontFamily: ui,
				contentFontFamily: content,
				codeFontFamily: code
			)
		}
		save(profile())
		#expect(applications == 1)
		#expect(colorRefreshes == 1)
		for (index, change) in [
			profile(ui: "Arial"),
			profile(content: "Georgia"),
			profile(code: "Menlo"),
			profile(preset: "og")
		].enumerated()
		{
			save(change)
			#expect(applications == index + 2)
		}
		save(
			profile(preset: "og"),
			mode: .dark
		)
		#expect(applications == 6)
		#expect(colorRefreshes == 6)
		size = TypographyConfiguration(uiSize: 16)
		center.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		#expect(field.font?.pointSize == 16)
		#expect(field.stringValue == "Retained content")
		#expect(applications == 7)
		// Notifications from older/manual publishers still refresh conservatively.
		center.post(
			name: ColorPreferences.didChange,
			object: nil
		)
		#expect(applications == 8)
		withExtendedLifetime(colorConsumer)
		{
		}
	}
}
