import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopActionButtonTests
{
	@Test func nativeActionUsesCurrentClosureAndCanBeCleared() throws
	{
		_ = NSApplication.shared
		var actions: [String] = []
		let button = DesktopActionButton(
			title: "Save",
			presentation: .secondary
		)
		{
			actions.append("original")
		}
		#expect(button.dispatchConfiguredAction())
		button.onAction =
		{
			actions.append("replacement")
		}
		#expect(button.dispatchConfiguredAction())
		button.onAction = nil
		#expect(button.dispatchConfiguredAction())
		#expect(actions == ["original", "replacement"])
	}

	@Test func tabActionsKeepOriginalIdentityWhenTitlesIncludeCounts() throws
	{
		_ = NSApplication.shared
		var selected: [String] = []
		let tabs = SettingsManagementTabs(
			titles: ["Installed", "Available"],
			selected: "Installed",
			counts: ["Installed": 3, "Available": 12]
		)
		{
			selected.append($0)
		}
		let buttons = tabs.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}
		#expect(buttons.count == 2)
		let installed = try #require(buttons.first)
		let available = try #require(buttons.last)
		#expect(installed.title == "Installed  3")
		#expect(available.title == "Available  12")
		#expect(installed.accessibilityValue() as? String == "Selected")
		#expect(available.dispatchConfiguredAction())
		#expect(installed.dispatchConfiguredAction())
		#expect(selected == ["Available", "Installed"])
	}
}
