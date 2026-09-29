import AppKit

struct PaletteCommand: Equatable
{
	enum Destination: Equatable
	{
		case project(URL)
		case conversation(String)
		case action(String)
	}

	let title: String
	let detail: String
	let destination: Destination
}

@MainActor
final class CommandPaletteController: NSViewController, NSTableViewDataSource,
	NSTableViewDelegate, NSSearchFieldDelegate
{
	var onChoose: ((PaletteCommand.Destination) -> Void)?

	private let searchField = NSSearchField()
	private let tableView = NSTableView()
	private let emptyLabel = NSTextField(labelWithString: "No matching commands")
	private let closeButton = NSButton(
		title: "Close",
		target: nil,
		action: nil
	)
	private var commands: [PaletteCommand] = []
	private var visibleCommands: [PaletteCommand] = []

	override func loadView()
	{
		let container = NSView()
		searchField.placeholderString = "Find a project, conversation, or action"
		searchField.setAccessibilityLabel("Search commands")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
		tableView.addTableColumn(column)
		tableView.headerView = nil
		tableView.rowHeight = 42
		tableView.delegate = self
		tableView.dataSource = self
		tableView.target = self
		tableView.doubleAction = #selector(chooseSelected)
		tableView.setAccessibilityLabel("Matching projects, conversations, and actions")
		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true

		emptyLabel.textColor = .secondaryLabelColor
		closeButton.target = self
		closeButton.action = #selector(close)
		closeButton.setAccessibilityLabel("Close command palette")
		let stack = AppKitLayout.verticalStack([searchField, scrollView, emptyLabel, closeButton])
		AppKitLayout.pin(
			stack,
			to: container
		)
		scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
		view = container
	}

	func present(
		in window: NSWindow,
		commands: [PaletteCommand]
	)
	{
		self.commands = commands
		searchField.stringValue = ""
		filterCommands()
		let sheet = NSWindow(contentViewController: self)
		sheet.title = "Command Palette"
		sheet.setContentSize(NSSize(
			width: min(
				560,
				max(
					400,
					window.frame.width - 80
				)
			),
			height: 360
		))
		window.beginSheet(sheet)
		{
			[weak self] _ in self?.onChoose = nil
		}
		sheet.makeFirstResponder(searchField)
	}

	func controlTextDidChange(_ notification: Notification)
	{
		filterCommands()
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy selector: Selector
	) -> Bool
	{
		if selector == #selector(NSResponder.insertNewline(_:))
		{
			chooseSelected()
			return true
		}
		if selector == #selector(NSResponder.moveDown(_:))
		{
			let lastCommandRow = max(
				0,
				visibleCommands.count - 1
			)
			let nextCommandRow = min(
				tableView.selectedRow + 1,
				lastCommandRow
			)
			tableView.selectRowIndexes(
				IndexSet(integer: nextCommandRow),
				byExtendingSelection: false
			)
			return true
		}
		if selector == #selector(NSResponder.cancelOperation(_:))
		{
			close()
			return true
		}
		return false
	}

	private func filterCommands()
	{
		let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		visibleCommands = commands.filter
		{
			query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
				|| $0.detail.localizedCaseInsensitiveContains(query)
		}
		tableView.reloadData()
		if visibleCommands.isEmpty
		{
			tableView.deselectAll(nil)
		}
		else
		{
			tableView.selectRowIndexes(
				IndexSet(integer: 0),
				byExtendingSelection: false
			)
		}
		emptyLabel.isHidden = !visibleCommands.isEmpty
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		visibleCommands.count
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard visibleCommands.indices.contains(row)
		else
		{
			return nil
		}
		let command = visibleCommands[row]
		let cell = NSTableCellView()
		let title = NSTextField(labelWithString: command.title)
		title.font = .systemFont(
			ofSize: 13,
			weight: .medium
		)
		title.lineBreakMode = .byTruncatingTail

		let detail = NSTextField(labelWithString: command.detail)
		detail.font = .systemFont(ofSize: 11)
		detail.textColor = .secondaryLabelColor
		detail.lineBreakMode = .byTruncatingMiddle

		let stack = AppKitLayout.verticalStack([title, detail])
		stack.spacing = 2
		AppKitLayout.pin(
			stack,
			to: cell,
			inset: 4
		)
		cell.setAccessibilityLabel("\(command.title), \(command.detail)")
		return cell
	}

	@objc private func chooseSelected()
	{
		guard visibleCommands.indices.contains(tableView.selectedRow)
		else
		{
			return
		}
		let destination = visibleCommands[tableView.selectedRow].destination
		let handler = onChoose
		if let sheet = view.window, let parent = sheet.sheetParent
		{
			parent.endSheet(sheet)
		}
		Task
		{
			@MainActor in handler?(destination)
		}
	}

	@objc private func close()
	{
		if let sheet = view.window, let parent = sheet.sheetParent
		{
			parent.endSheet(sheet)
		}
	}
}
