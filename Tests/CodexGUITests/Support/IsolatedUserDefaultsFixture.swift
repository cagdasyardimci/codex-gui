import Foundation
import Testing

/// The caller retains this fixture and defers cleanup until its test or loop iteration ends.
struct IsolatedUserDefaultsFixture
{
	let defaults: UserDefaults
	let suiteName: String

	init(prefix: String) throws
	{
		suiteName = "\(prefix).\(UUID().uuidString)"
		defaults = try #require(UserDefaults(suiteName: suiteName))
		defaults.removePersistentDomain(forName: suiteName)
	}

	func cleanup()
	{
		defaults.removePersistentDomain(forName: suiteName)
	}
}
