import Foundation

/// A local choice of which advertised efforts appear in pickers, independent of model settings.
struct ReasoningEffortVisibility
{
	static let requiredVisibleEfforts: Set<String> = ["low", "medium", "high", "xhigh"]
	private static let hiddenKey = "settings.hiddenReasoningEfforts"
	private let defaults: UserDefaults

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	func isVisible(_ effort: String) -> Bool
	{
		!hiddenEfforts.contains(effort)
	}

	func setVisible(
		_ visible: Bool,
		effort: String
	)
	{
		guard !effort.isEmpty
		else
		{
			return
		}
		var hidden = hiddenEfforts
		if visible
		{
			hidden.remove(effort)
		}
		else if !Self.requiredVisibleEfforts.contains(effort)
		{
			hidden.insert(effort)
		}
		defaults.set(
			hidden.sorted(),
			forKey: Self.hiddenKey
		)
	}

	/// Preserve the current supported selection even when it is hidden for future selections.
	func visibleEfforts(
		advertised: [String],
		retaining selection: String?
	) -> [String]
	{
		let hidden = hiddenEfforts
		var seen = Set<String>()
		return advertised.filter
		{
			!$0.isEmpty && seen.insert($0).inserted && (!hidden.contains($0) || $0 == selection)
		}
	}

	private var hiddenEfforts: Set<String>
	{
		Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
			.subtracting(Self.requiredVisibleEfforts)
	}
}
