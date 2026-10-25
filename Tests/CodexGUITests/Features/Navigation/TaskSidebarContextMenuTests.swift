import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TaskSidebarContextMenuTests
{

	@Test func menuActionsKeepCapturedTaskCallbacksAfterCellReuse() throws
	{
		_ = NSApplication.shared
		let cell = TaskSidebarCellView(frame: .zero)
		var invoked: [String] = []
		cell.onRename =
		{
			invoked.append("rename")
		}
		cell.onTogglePin =
		{
			invoked.append("pin")
		}
		cell.onMarkUnread =
		{
			invoked.append("unread")
		}
		cell.onArchive =
		{
			invoked.append("archive")
		}
		cell.onDelete =
		{
			invoked.append("delete")
		}
		let menu = cell.makeContextMenu()
		cell.onRename =
		{
			invoked.append("wrong task")
		}
		cell.onTogglePin = nil
		cell.onMarkUnread = nil
		cell.onArchive = nil
		cell.onDelete = nil
		for item in menu.items where !item.isSeparatorItem
		{
			let action = try #require(item.action)
			#expect(item.isEnabled)
			#expect(NSApplication.shared.sendAction(
				action,
				to: item.target,
				from: item
			))
		}
		#expect(invoked == ["rename", "pin", "unread", "archive", "delete"])
	}

	@Test func unavailableAndDestructivelyBlockedActionsRemainVisibleButDisabled()
	{
		_ = NSApplication.shared
		let cell = TaskSidebarCellView(frame: .zero)
		cell.onRename =
		{
		}
		cell.onTogglePin =
		{
		}
		cell.onMarkUnread =
		{
		}
		cell.onArchive =
		{
		}
		cell.onDelete =
		{
		}
		cell.setActionsEnabled(false)
		let menu = cell.makeContextMenu()
		#expect(!menu.items[0].isEnabled)
		#expect(menu.items[1 ... 2].allSatisfy
		{
			$0.isEnabled
		})
		#expect(!menu.items[4].isEnabled)
		#expect(!menu.items[5].isEnabled)
		cell.onRename = nil
		#expect(!cell.makeContextMenu().items[0].isEnabled)
	}
}
