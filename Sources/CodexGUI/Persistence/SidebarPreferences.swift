import Foundation

/// Presentation preferences do not change backend conversation order or project ownership.
final class SidebarPreferences
{
	enum Organization: String, CaseIterable
	{
		case byProject, oneList
		var title: String
		{
			self == .byProject ? "By project" : "In one list"
		}
	}

	enum SortOrder: String, CaseIterable
	{
		case lastUpdated, manual
		var title: String
		{
			self == .lastUpdated ? "Last updated" : "Manual order"
		}
	}

	private let defaults: UserDefaults
	private let prefix = "sidebar."

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	var organization: Organization
	{
		get
		{
			Organization(rawValue: defaults.string(forKey: prefix + "organization") ?? "") ??
				.byProject
		}
		set
		{
			defaults.set(
				newValue.rawValue,
				forKey: prefix + "organization"
			)
		}
	}

	var sortOrder: SortOrder
	{
		get
		{
			SortOrder(rawValue: defaults.string(forKey: prefix + "sortOrder") ?? "") ??
				.lastUpdated
		}
		set
		{
			defaults.set(
				newValue.rawValue,
				forKey: prefix + "sortOrder"
			)
		}
	}

	var manualThreadIDs: [String]
	{
		get
		{
			defaults.stringArray(forKey: prefix + "manualThreadIDs") ?? []
		}
		set
		{
			defaults.set(
				newValue,
				forKey: prefix + "manualThreadIDs"
			)
		}
	}
}
