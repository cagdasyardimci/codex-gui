import Foundation

/// Keeps UI test preferences separate while retaining the signed application identity.
enum ApplicationPreferences
{
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
