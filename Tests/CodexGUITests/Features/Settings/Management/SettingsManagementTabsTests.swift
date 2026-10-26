import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsManagementTabsTests
{
	@Test func countedTabsKeepTheirIdentityAndLabelsWhenSelectionChanges() throws
	{
		_ = NSApplication.shared
		var selections: [String] = []
		let tabs = SettingsManagementTabs(
			titles: ["Installed", "Available"],
			selected: "Installed",
			counts: ["Installed": 2, "Available": 12]
		)
		{
			selections.append($0)
		}
		let buttons = tabs.arrangedSubviews.compactMap
		{
			$0 as? DesktopStyledButton
		}
		try #require(buttons.count == 2)
		#expect(buttons.map(\.title) == ["Installed  2", "Available  12"])
		#expect(buttons[0].accessibilityValue() as? String == "Selected")
		#expect(buttons[1].dispatchConfiguredAction())
		#expect(selections == ["Available"])

		tabs.select(title: "Available")

		#expect(buttons.map(\.title) == ["Installed  2", "Available  12"])
		#expect(buttons[0].accessibilityValue() as? String == "")
		#expect(buttons[1].accessibilityValue() as? String == "Selected")
		for (index, button) in buttons.enumerated()
		{
			guard case let .tab(selected) = button.presentation
			else
			{
				Issue.record("A settings tab lost its tab presentation.")
				continue
			}
			#expect(selected == (index == 1))
		}
		#expect(selections == ["Available"])
	}
}
