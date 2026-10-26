import Foundation
import Testing

@testable import CodexGUI

struct ReasoningEffortVisibilityTests
{
	@Test func filterPersistsHiddenEffortsAndAdmitsNewAdvertisedValues() throws
	{
		let suite = "ReasoningEffortVisibilityTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let visibility = ReasoningEffortVisibility(defaults: defaults)
		#expect(visibility.visibleEfforts(
			advertised: ["low", "medium", "high"],
			retaining: nil
		)
			== ["low", "medium", "high"])
		visibility.setVisible(
			false,
			effort: "max"
		)
		let reloaded =
			ReasoningEffortVisibility(defaults: try #require(UserDefaults(suiteName: suite)))
		#expect(!reloaded.isVisible("max"))
		#expect(reloaded.visibleEfforts(
			advertised: ["low", "medium", "high", "max", "future"],
			retaining: nil
		) == ["low", "medium", "high", "future"])
		reloaded.setVisible(
			true,
			effort: "max"
		)
		#expect(visibility.isVisible("max"))
		#expect(visibility.visibleEfforts(
			advertised: ["max"],
			retaining: nil
		) == ["max"])
	}

	@Test func hiddenCurrentSelectionIsRetainedWithoutInventingModelSupport() throws
	{
		let suite = "ReasoningEffortVisibilityTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let visibility = ReasoningEffortVisibility(defaults: defaults)
		visibility.setVisible(
			false,
			effort: "max"
		)
		visibility.setVisible(
			false,
			effort: "ultra"
		)
		#expect(visibility.visibleEfforts(
			advertised: ["max", "ultra", "ultra", ""],
			retaining: "ultra"
		)
			== ["ultra"])
		#expect(visibility.visibleEfforts(
			advertised: ["max", "ultra"],
			retaining: "unsupported"
		)
		.isEmpty)
		#expect(!visibility.isVisible("ultra"))
		#expect(visibility.visibleEfforts(
			advertised: [],
			retaining: "ultra"
		).isEmpty)
	}

	@Test func requiredEffortsIgnoreLegacyHiddenEntriesAndWritesRemoveThoseEntries() throws
	{
		let suite = "ReasoningEffortVisibilityTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let legacyHidden = ["low", "xhigh", "max"]
		defaults.set(
			legacyHidden,
			forKey: "settings.hiddenReasoningEfforts"
		)
		let visibility = ReasoningEffortVisibility(defaults: defaults)
		#expect(visibility.isVisible("low"))
		#expect(visibility.isVisible("xhigh"))
		#expect(!visibility.isVisible("max"))
		#expect(visibility.visibleEfforts(
			advertised: ["low", "medium", "max"],
			retaining: nil
		) == ["low", "medium"])
		#expect(defaults.stringArray(forKey: "settings.hiddenReasoningEfforts") == legacyHidden)

		for effort in ReasoningEffortVisibility.requiredVisibleEfforts
		{
			visibility.setVisible(
				false,
				effort: effort
			)
			#expect(visibility.isVisible(effort))
		}
		#expect(defaults.stringArray(forKey: "settings.hiddenReasoningEfforts") == ["max"])
		visibility.setVisible(
			false,
			effort: "ultra"
		)
		#expect(!visibility.isVisible("ultra"))
		#expect(defaults.stringArray(forKey: "settings.hiddenReasoningEfforts") == ["max", "ultra"])
	}
}
