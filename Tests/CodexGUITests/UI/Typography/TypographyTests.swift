import AppKit
import Testing

@testable import CodexGUI

struct TypographyTests
{
	static let measurements: [CGFloat] = [11, 13, 14, 15, 16]

	@Test func invalidPreferencesAreNormalized()
	{
		#expect(TypographyConfiguration(
			uiSize: .nan,
			contentSize: .nan,
			codeSize: .infinity
		) == .standard)
		#expect(TypographyConfiguration(
			uiSize: 0,
			contentSize: 100,
			codeSize: 100
		) == TypographyConfiguration(
			uiSize: 11,
			contentSize: 24,
			codeSize: 24
		))
		#expect(TypographyConfiguration(
			uiSize: 13.6,
			codeSize: 11.2
		) == TypographyConfiguration(
			uiSize: 14,
			codeSize: 11
		))
	}

}

@MainActor
struct TypographyBindingTests
{
	@Test func legacyPreferencesGainContentSizeWithoutChangingOtherScopes() throws
	{
		let name = "TypographyMigration.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		defaults.set(
			["ui": 13, "code": 16],
			forKey: "appearance.typography"
		)
		let preferences = TypographyPreferences(defaults: defaults)
		#expect(preferences.configuration == TypographyConfiguration(
			uiSize: 13,
			codeSize: 16
		))
		preferences.save(
			TypographyConfiguration(
				uiSize: 13,
				contentSize: 21,
				codeSize: 16
			),
			center: NotificationCenter()
		)
		#expect(TypographyPreferences(defaults: defaults).configuration.contentSize == 21)
		#expect(defaults.dictionary(forKey: "appearance.typography")?["ui"] as? Int == 13)
		#expect(defaults.dictionary(forKey: "appearance.typography")?["code"] as? Int == 16)
	}

}

@MainActor
private final class ConfigurationState
{
	var value = TypographyConfiguration.standard
}
