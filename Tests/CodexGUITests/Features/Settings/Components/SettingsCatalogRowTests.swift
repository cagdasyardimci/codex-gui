import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsCatalogRowTests
{
	@Test func catalogRowRoutesActionsAndRestoresToggleUntilItsOwnerPublishes() throws
	{
		_ = NSApplication.shared
		var changes: [Bool] = []
		var opens = 0
		let row = SettingsCatalogRow(
			title: "Example plugin",
			details: ["Description", "Workspace policy"],
			accessories: [
				.toggle(.init(
					label: "Example plugin",
					isOn: false
				)
				{
					changes.append($0)
				}),
				.action(.init(
					title: "View Example plugin",
					icon: .chevronRight
				)
				{
					opens += 1
				})
			]
		)
		let toggle = try #require(descendants(row).compactMap
		{
			$0 as? DesktopSwitch
		}.first)
		let open = try #require(descendants(row).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "View Example plugin"
		})
		toggle.state = .on
		#expect(toggle.dispatchConfiguredAction())
		#expect(changes == [true])
		#expect(toggle.state == .off)
		#expect(open.dispatchConfiguredAction())
		#expect(opens == 1)
		let text = descendants(row).compactMap
		{
			$0 as? NSTextField
		}.map(\.stringValue)
		#expect(text.contains("Example plugin"))
		#expect(text.contains("Description"))
		#expect(text.contains("Workspace policy"))
	}

	@Test func unavailableCatalogActionsKeepTheirHelpAndDoNotDispatch() throws
	{
		_ = NSApplication.shared
		var attempts = 0
		let row = SettingsCatalogRow(
			title: "Restricted plugin",
			details: ["Workspace policy"],
			accessories: [.action(.init(
				title: "Install",
				enabled: false,
				help: "Workspace policy"
			)
			{
				attempts += 1
			})]
		)
		let install = try #require(descendants(row).compactMap
		{
			$0 as? NSButton
		}.first)
		#expect(install.toolTip == "Workspace policy")
		#expect(!install.dispatchConfiguredAction())
		#expect(attempts == 0)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
