import Foundation

struct ColorPreferences
{
	private final class ConfigurationCache: @unchecked Sendable
	{
		private let lock = NSLock()
		private var values: [Data: ColorThemeConfiguration] = [:]

		func configuration(for data: Data) -> ColorThemeConfiguration
		{
			lock.lock()
			defer
			{
				lock.unlock()
			}
			if let cached = values[data]
			{
				return cached
			}
			let value = (try? JSONDecoder().decode(
				ColorThemeConfiguration.self,
				from: data
			))
				?? ColorThemeConfiguration()
			if values.count >= 16
			{
				values.removeAll(keepingCapacity: true)
			}
			values[data] = value
			return value
		}
	}

	private static let configurationCache = ConfigurationCache()
	static let didChange = Notification.Name("CodexGUI.colorThemeDidChange")
	static let typographyChangedKey = "typographyChanged"
	private let defaults: UserDefaults
	private let key = "appearance.colorTheme"

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	var configuration: ColorThemeConfiguration
	{
		guard let data = defaults.data(forKey: key)
		else
		{
			return ColorThemeConfiguration()
		}
		return Self.configurationCache.configuration(for: data)
	}

	@MainActor
	func save(
		_ configuration: ColorThemeConfiguration,
		center: NotificationCenter = .default
	)
	{
		let previous = self.configuration
		guard configuration != previous,
				let data = try? JSONEncoder().encode(configuration)
		else
		{
			return
		}
		defaults.set(
			data,
			forKey: key
		)
		center.post(
			name: Self.didChange,
			object: nil,
			userInfo: [Self.typographyChangedKey: previous.mode != configuration.mode
				|| !Self.sameFonts(
					previous.light,
					configuration.light
				)
				|| !Self.sameFonts(
					previous.dark,
					configuration.dark
				)]
		)
	}
	private static func sameFonts(
		_ lhs: ColorThemeProfile,
		_ rhs: ColorThemeProfile
	) -> Bool
	{
		// Preset changes can change inherited families even without explicit overrides.
		lhs.presetID == rhs.presetID && lhs.uiFontFamily == rhs.uiFontFamily
			&& lhs.contentFontFamily == rhs.contentFontFamily && lhs.codeFontFamily == rhs
			.codeFontFamily
	}

}
