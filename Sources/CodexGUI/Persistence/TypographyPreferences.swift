import Foundation

/// Store typography bases together so readers cannot observe a partially updated configuration.
struct TypographyPreferences
{
	static let didChange = Notification.Name("CodexGUI.typographyDidChange")
	private let defaults: UserDefaults
	private let key = "appearance.typography"

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	var configuration: TypographyConfiguration
	{
		let values = defaults.dictionary(forKey: key) ?? [:]
		return TypographyConfiguration(
			uiSize: (values["ui"] as? NSNumber).map
			{
				CGFloat($0.doubleValue)
			} ?? 14,
			contentSize: (values["content"] as? NSNumber).map
			{
				CGFloat($0.doubleValue)
			} ?? 15,
			codeSize: (values["code"] as? NSNumber).map
			{
				CGFloat($0.doubleValue)
			} ?? 12
		)
	}

	@MainActor
	func save(
		_ configuration: TypographyConfiguration,
		center: NotificationCenter = .default
	)
	{
		guard configuration != self.configuration
		else
		{
			return
		}
		defaults.set(
			["ui": Double(configuration.uiSize),
				"content": Double(configuration.contentSize),
				"code": Double(configuration.codeSize)],
			forKey: key
		)
		center.post(
			name: Self.didChange,
			object: nil
		)
	}
}
