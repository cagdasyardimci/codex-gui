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

	private let searchField = NSSearchField()
	private let explanationLabel = NSTextField(wrappingLabelWithString: "")
	private let tableView = NSTableView()
	private let emptyLabel = NSTextField(labelWithString: "No matching commands")
	private let closeButton = NSButton(
		title: "Close",
		target: nil,
		action: nil
	)
	private var commands: [PaletteCommand] = []
	private var visibleCommands: [PaletteCommand] = []
	private var presentationRevision = 0

	override func loadView()
	{
		let container = NSView()
		configureSearchField()
		let scrollView = makeCommandsScrollView()
		configureStatusAndCloseControls()

		let stack = AppKitLayout.verticalStack([
			explanationLabel,
			searchField,
			scrollView,
			emptyLabel,
			closeButton
		])
		AppKitLayout.pin(
			stack,
			to: container
		)
		scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
		view = container
	}

	private func configureSearchField()
	{
		searchField.placeholderString = "Find a project, conversation, or action"
		searchField.setAccessibilityLabel("Search commands")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true
	}

	private func makeCommandsScrollView() -> NSScrollView
	{
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
		return scrollView
	}

	private func configureStatusAndCloseControls()
	{
		emptyLabel.textColor = .secondaryLabelColor
		closeButton.target = self
		closeButton.action = #selector(close)
		closeButton.setAccessibilityLabel("Close command palette")
		explanationLabel.textColor = .secondaryLabelColor
		explanationLabel.font = .systemFont(ofSize: 12)
		explanationLabel.isHidden = true
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
		guard window.attachedSheet == nil
		else
		{
			return
		}
		presentationRevision += 1
		let revision = presentationRevision
		_ = view
		self.commands = commands
		explanationLabel.stringValue = informativeText ?? ""
		explanationLabel.isHidden = informativeText == nil
		searchField.placeholderString = searchPlaceholder
		searchField.setAccessibilityLabel(searchPlaceholder)
		emptyLabel.stringValue = emptyMessage
		searchField.stringValue = ""
		filterCommands()
		let sheet = NSWindow(contentViewController: self)
		sheet.title = title
		sheet.setContentSize(NSSize(
			width: min(
				560,
				max(
					400,
					window.frame.width - 80
				)
			),
			height: informativeText == nil ? 360 : 420
		))
		window.beginSheet(sheet)
		{
			[weak self] _ in
			guard let self, self.presentationRevision == revision
			else
			{
				return
			}
			self.onChoose = nil
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
		let title = makeCommandTitle(command)
		let detail = makeCommandDetail(command)

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

	private func makeCommandTitle(_ command: PaletteCommand) -> NSTextField
	{
		let title = NSTextField(labelWithString: command.title)
		title.font = .systemFont(
			ofSize: 13,
			weight: .medium
		)
		title.lineBreakMode = .byTruncatingTail
		title.textColor = command.isEnabled ? .labelColor : .tertiaryLabelColor

		return title
	}

	private func makeCommandDetail(_ command: PaletteCommand) -> NSTextField
	{
		let detail = NSTextField(labelWithString: command.detail)
		detail.font = .systemFont(ofSize: 11)
		detail.textColor = .secondaryLabelColor
		detail.lineBreakMode = .byTruncatingMiddle

		return detail
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
