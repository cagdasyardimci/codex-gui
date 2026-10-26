import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsArchivedChatRowTests
{
	@Test func archiveActionsRetainTheirIndependentCallbacksAndRespectBusyState() throws
	{
		_ = NSApplication.shared
		for enabled in [true, false]
		{
			var actions: [String] = []
			let row = SettingsArchivedChatRow(
				title: "An archived chat",
				date: "Yesterday",
				isEnabled: enabled,
				onUnarchive:
				{
					actions.append("unarchive")
				},
				onDelete:
				{
					actions.append("delete")
				}
			)
			let buttons = descendants(row).compactMap
			{
				$0 as? NSButton
			}
			let restore = try #require(buttons.first
			{
				$0.title == "Unarchive"
			})
			let delete = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Delete An archived chat"
			})
			#expect(restore.dispatchConfiguredAction() == enabled)
			#expect(delete.dispatchConfiguredAction() == enabled)
			#expect(actions == (enabled ? ["unarchive", "delete"] : []))
			let title = try #require(descendants(row).compactMap
			{
				$0 as? NSTextField
			}.first
			{
				$0.stringValue == "An archived chat"
			})
			#expect(title.toolTip == "An archived chat")
			#expect(title.lineBreakMode == .byTruncatingTail)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
