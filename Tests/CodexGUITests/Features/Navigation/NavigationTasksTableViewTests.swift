import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationTasksTableViewTests
{
	@Test func rightClickOnTaskTitleAndRowWhitespaceUsesClickedRowWithoutChangingSelection() throws
	{
		let fixture = TableFixture()
		defer
		{
			fixture.window.close()
		}
		let cell = try #require(fixture.table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		) as? TaskSidebarCellView)
		cell.layoutSubtreeIfNeeded()
		let title = try #require(cell.textField)
		let titlePoint = title.convert(
			NSPoint(
				x: title.bounds.midX,
				y: title.bounds.midY
			),
			to: fixture.table
		)
		let rowRect = fixture.table.rect(ofRow: 1)
		var requestedRows: [Int] = []
		let expectedMenu = NSMenu(title: "Clicked task")
		fixture.table.onContextMenuForRow =
		{
			row in
			requestedRows.append(row)
			return expectedMenu
		}
		fixture.table.selectRowIndexes(
			IndexSet(integer: 0),
			byExtendingSelection: false
		)
		for point in [
			titlePoint,
			NSPoint(
				x: rowRect.minX + 2,
				y: rowRect.midY
			),
			NSPoint(
				x: rowRect.maxX - 2,
				y: rowRect.midY
			),
		]
		{
			let event = try fixture.rightClick(at: point)
			#expect(fixture.table.menu(for: event) === expectedMenu)
			#expect(fixture.table.selectedRowIndexes == IndexSet(integer: 0))
		}
		#expect(requestedRows == [1, 1, 1])
	}

	@Test func rightClickOutsideRowsDoesNotRequestTaskMenu() throws
	{
		let fixture = TableFixture()
		defer
		{
			fixture.window.close()
		}
		var requestedRows: [Int] = []
		fixture.table.onContextMenuForRow =
		{
			row in
			requestedRows.append(row)
			return NSMenu(title: "Unexpected")
		}
		let rowRect = fixture.table.rect(ofRow: 1)
		for point in [
			NSPoint(
				x: 20,
				y: rowRect.maxY + 30
			),
			NSPoint(
				x: -10,
				y: rowRect.midY
			),
			NSPoint(
				x: fixture.table.bounds.maxX + 10,
				y: rowRect.midY
			),
		]
		{
			let event = try fixture.rightClick(at: point)
			#expect(fixture.table.menu(for: event) == nil)
		}
		#expect(requestedRows.isEmpty)
	}

	@MainActor
	private final class TableFixture: NSObject, NSTableViewDataSource, NSTableViewDelegate
	{
		let window: NSWindow
		let table: NavigationTasksTableView

		override init()
		{
			_ = NSApplication.shared
			window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 360,
					height: 200
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			table = NavigationTasksTableView(frame: NSRect(
				x: 20,
				y: 30,
				width: 280,
				height: 140
			))
			super.init()
			window.contentView?.addSubview(table)
			table.headerView = nil
			table.rowHeight = 30
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
			column.width = 280
			table.addTableColumn(column)
			table.dataSource = self
			table.delegate = self
			table.reloadData()
			table.layoutSubtreeIfNeeded()
		}

		func numberOfRows(in tableView: NSTableView) -> Int
		{
			2
		}

		func tableView(
			_ tableView: NSTableView,
			viewFor tableColumn: NSTableColumn?,
			row: Int
		) -> NSView?
		{
			let cell = TaskSidebarCellView(frame: .zero)
			cell.textField?.stringValue = "Task \(row)"
			return cell
		}

		func rightClick(at point: NSPoint) throws -> NSEvent
		{
			try #require(NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: table.convert(
					point,
					to: nil
				),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			))
		}
	}
}
