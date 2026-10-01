import AppKit

/// A native list whose selection stays separate from the composer's insertion point.
@MainActor
final class SlashCommandPopoverView: NSViewController, NSTableViewDataSource, NSTableViewDelegate
{
	private var rowCount: Int
	{
		commands.count
	}
	var onChoose: ((SlashCommandDescriptor) -> Void)?
	var unavailableReason: ((SlashCommandID) -> String?)?
	private let table = NSTableView()
	private let scroll = NSScrollView()
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
		table.style = .plain
		table.rowHeight = 28
		table.intercellSpacing = .zero
		table.backgroundColor = .clear
		table.selectionHighlightStyle = .regular
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(chooseSelected)
		table.setAccessibilityLabel("Slash commands. Use arrow keys to select, Tab to insert, "
			+ "Return to run, Escape to dismiss.")
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		emptyLabel.textColor = .secondaryLabelColor
		let stack = AppKitLayout.verticalStack(
			[scroll, emptyLabel],
			spacing: 4
		)
		let container = DesktopSurface(
			DesktopTheme.slashMenu,
			cornerRadius: 22,
			bordered: true
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 4
		)
		scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		view = container
		preferredContentSize = NSSize(
			width: 720,
			height: 316
		)
	}

	func render(prefix: String)
	{
		_ = view
		let previous = selectedCommand?.id
		commands = SlashCommandRegistry.matching(prefix: prefix)
		let height = CGFloat(min(
			11,
			max(
				1,
				rowCount
			)
		)) * table.rowHeight
		scroll.isHidden = rowCount == 0
		preferredContentSize.height = height + 8
		table.reloadData()
		emptyLabel.isHidden = rowCount > 0
		guard rowCount > 0
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
		guard rowCount > 0
		else
		{
			return
		}
		selectRow(min(
			max(
				0,
				table.selectedRow + delta
			),
			rowCount - 1
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
		rowCount
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
		let presentation = SlashCommandMenuPresentation(command.id)
		let title = NSTextField(labelWithString: presentation.title)
		title.font = .systemFont(ofSize: 13)
		title.textColor = reason == nil ? .labelColor : .secondaryLabelColor
		title.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)

		let detail = NSTextField(labelWithString: command.description)
		detail.font = .systemFont(ofSize: 13)
		detail.textColor = .tertiaryLabelColor
		detail.lineBreakMode = .byTruncatingTail
		detail.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		detail.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)

		let icon = NSImageView()
		icon.image = NSImage(
			systemSymbolName: presentation.symbol,
			accessibilityDescription: nil
		)
		icon.contentTintColor = .secondaryLabelColor
		icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
		let contents = AppKitLayout.horizontalStack(
			[icon, title, detail],
			spacing: 8
		)
		if presentation.opensPicker
		{
			let chevron = NSImageView()
			chevron.image = NSImage(
				systemSymbolName: "chevron.right",
				accessibilityDescription: nil
			)
			chevron.contentTintColor = .tertiaryLabelColor
			chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
			chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true
			contents.addArrangedSubview(chevron)
		}
		contents.distribution = .fill
		let cell = NSTableCellView()
		cell.addSubview(contents)
		contents.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			contents.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor,
				constant: 10
			),
			contents.trailingAnchor.constraint(
				equalTo: cell.trailingAnchor,
				constant: -10
			),
			contents.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		cell.toolTip = reason ?? command.description
		cell.setAccessibilityLabel("/\(command.name). \(command.description)"
			+ (reason.map
			{
				". " + $0
			} ?? ""))
		return cell
	}

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		return SlashCommandMenuRowView()
	}

	@objc private func chooseSelected()
	{
		if let selectedCommand
		{
			onChoose?(selectedCommand)
		}
	}
}
