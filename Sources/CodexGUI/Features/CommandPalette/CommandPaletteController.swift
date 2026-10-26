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
	var isEnabled = true
}

@MainActor
final class CommandPaletteController: NSViewController, NSTableViewDataSource,
	NSTableViewDelegate, NSSearchFieldDelegate
{
	var onChoose: ((PaletteCommand.Destination) -> Void)?

	private let searchView = DesktopSearchSheetView(presentation: .commands)
	private var searchField: DesktopSearchField
	{
		searchView.query
	}
	private var tableView: NSTableView
	{
		searchView.table
	}
	private var commands: [PaletteCommand] = []
	private var visibleCommands: [PaletteCommand] = []

	override func loadView()
	{
		configureSearchField()
		tableView.delegate = self
		tableView.dataSource = self
		tableView.target = self
		tableView.doubleAction = #selector(chooseSelected)
		searchView.onClose =
		{
			[weak self] in self?.close()
		}
		view = searchView
	}

	private func configureSearchField()
	{
		searchField.configureSearch(
			placeholder: "Find a project, conversation, or action",
			accessibilityLabel: "Search commands",
			delegate: self,
			sendsImmediately: true
		)
	}

	func present(
		in window: NSWindow,
		commands: [PaletteCommand],
		title: String = "Command Palette",
		searchPlaceholder: String = "Find a project, conversation, or action",
		emptyMessage: String = "No matching commands",
		informativeText: String? = nil
	)
	{
		_ = view
		self.commands = commands
		searchView.explanation = informativeText
		searchField.placeholderString = searchPlaceholder
		searchField.setAccessibilityLabel(searchPlaceholder)
		searchView.emptyMessage = emptyMessage
		searchField.stringValue = ""
		filterCommands()
		let sheet = NSWindow(contentViewController: self)
		sheet.title = title
		searchView.resize(
			window: sheet,
			relativeTo: window
		)
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
				IndexSet(integer: visibleCommands.firstIndex(where: \.isEnabled) ?? 0),
				byExtendingSelection: false
			)
		}
		searchView.hasResults = !visibleCommands.isEmpty
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
		let content = DesktopSearchResultContentView(presentation: .command(
			title: command.title,
			detail: command.detail,
			enabled: command.isEnabled
		))
		AppKitLayout.pin(
			content,
			to: cell,
			inset: 0
		)
		cell.setAccessibilityLabel(content.accessibilityLabel())
		return cell
	}

	func tableView(
		_ tableView: NSTableView,
		shouldSelectRow row: Int
	) -> Bool
	{
		visibleCommands.indices.contains(row) && visibleCommands[row].isEnabled
	}

	@objc private func chooseSelected()
	{
		guard visibleCommands.indices.contains(tableView.selectedRow),
				visibleCommands[tableView.selectedRow].isEnabled
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
