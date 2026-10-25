import Foundation

/// Keeps UI test preferences separate while retaining the signed application identity.
enum ApplicationPreferences
{
	private static let applicationDomain = "local.codexgui.appkit"

	/// Remote hosting follows the app across bundled and direct SwiftPM launches.
	static var remoteAccessStore: UserDefaults
	{
		if ProcessInfo.processInfo.environment["CODEX_GUI_PREFERENCES_SUITE"]?.isEmpty == false
		{
			return defaultStore
		}
		return UserDefaults(suiteName: applicationDomain) ?? .standard
	}

	static var defaultStore: UserDefaults
	{
		if let suite = ProcessInfo.processInfo.environment["CODEX_GUI_PREFERENCES_SUITE"],
			!suite.isEmpty,
			let defaults = UserDefaults(suiteName: suite)
		{
			return defaults
		}
		return .standard
	}
}
