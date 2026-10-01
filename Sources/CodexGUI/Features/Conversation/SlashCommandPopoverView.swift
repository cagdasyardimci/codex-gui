import AppKit

/// A native list whose selection stays separate from the composer's insertion point.
@MainActor
final class SlashCommandPopoverView: NSViewController, NSTableViewDataSource, NSTableViewDelegate
{
	var onChoose: ((SlashCommandDescriptor) -> Void)?
	var unavailableReason: ((SlashCommandID) -> String?)?
	private let table = NSTableView()
	private let emptyLabel = NSTextField(labelWithString: "No matching commands")
	private(set) var commands: [SlashCommandDescriptor] = []
	var selectedCommand: SlashCommandDescriptor?
	{
		commands.indices.contains(table.selectedRow) ? commands[table.selectedRow] : nil
	}

	override func loadView()
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("slashCommand"))
		table.addTableColumn(column)
		table.headerView = nil
		table.rowHeight = 48
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(chooseSelected)
		table.setAccessibilityLabel("Slash commands. Use arrow keys to select, Tab to insert, "
			+ "Return to run, Escape to dismiss.")
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		emptyLabel.textColor = .secondaryLabelColor
		let stack = AppKitLayout.verticalStack(
			[scroll, emptyLabel],
			spacing: 4
		)
		let container = DesktopSurface(
			DesktopTheme.chrome,
			cornerRadius: 12,
			bordered: true
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 6
		)
		scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scroll.heightAnchor.constraint(equalToConstant: 270).isActive = true
		view = container
		preferredContentSize = NSSize(
			width: 430,
			height: 294
		)
	}

	func render(prefix: String)
	{
		_ = view
		let previous = selectedCommand?.id
		commands = SlashCommandRegistry.matching(prefix: prefix)
		table.reloadData()
		emptyLabel.isHidden = !commands.isEmpty
		guard !commands.isEmpty
		else
		{
			table.deselectAll(nil); return
		}
		selectRow(commands.firstIndex(where:
			{
				$0.id == previous
			}) ?? 0)
	}

	func moveSelection(by delta: Int)
	{
		guard !commands.isEmpty
		else
		{
			return
		}
		selectRow(min(
			max(
				0,
				table.selectedRow + delta
			),
			commands.count - 1
		))
	}

	private func selectRow(_ index: Int)
	{
		table.selectRowIndexes(
			IndexSet(integer: index),
			byExtendingSelection: false
		)
		table.scrollRowToVisible(index)
		NSAccessibility.post(
			element: table,
			notification: .selectedRowsChanged
		)
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		commands.count
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard commands.indices.contains(row)
		else
		{
			return nil
		}
		let command = commands[row]
		let reason = unavailableReason?(command.id)
		let title = NSTextField(labelWithString: "/" + command.name)
		title.font = .systemFont(
			ofSize: 13,
			weight: .medium
		)
		let detail = NSTextField(labelWithString: reason ?? command.description)
		detail.font = .systemFont(ofSize: 11)
		detail.textColor = reason == nil ? .secondaryLabelColor : .systemOrange
		detail.lineBreakMode = .byTruncatingTail
		let cell = NSTableCellView()
		AppKitLayout.pin(
			AppKitLayout.verticalStack(
				[title, detail],
				spacing: 2
			),
			to: cell,
			inset: 5
		)
		cell.setAccessibilityLabel("/\(command.name). \(reason ?? command.description)")
		return cell
	}

	@objc private func chooseSelected()
	{
		if let selectedCommand
		{
			onChoose?(selectedCommand)
		}
	}
}
