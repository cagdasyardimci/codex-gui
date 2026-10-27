import AppKit

@MainActor
final class FileSearchController
{
	var onSearch: ((String, String?) -> Void)?
	var onChoose: ((FileViewerSearchResult) -> Void)?
	var onDismiss: (() -> Void)?
	var onCancelSearch: (() -> Void)?

	private lazy var panel = FileSearchPanel(mode: .content)

	init()
	{
		panel.onQuery =
		{
			[weak self] query, mask in self?.onSearch?(query, mask)
		}
		panel.onChooseContent =
		{
			[weak self] result in self?.onChoose?(result)
		}
		panel.onDismiss =
		{
			[weak self] in self?.onDismiss?()
		}
		panel.onCancelSearch =
		{
			[weak self] in self?.onCancelSearch?()
		}
	}

	func render(_ state: FileViewerState)
	{
		panel.render(state)
	}
	func present(in window: NSWindow)
	{
		panel.present(in: window)
	}
	func focusSearch()
	{
		panel.focusSearch()
	}
	func dismiss()
	{
		panel.dismiss()
	}
}

@MainActor
final class FileSearchPanel: NSViewController,
	NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate
{
	typealias Mode = DesktopFileSearchContentView.Mode
	var onQuery: ((String, String?) -> Void)?
	var onChooseFilename: ((FileLocation) -> Void)?
	var onChooseContent: ((FileViewerSearchResult) -> Void)?
	var onDismiss: (() -> Void)?
	var onCancelSearch: (() -> Void)?

	private let mode: Mode
	private let queryField = FileSearchTextField()
	private let maskField = FileSearchTextField()
	private let maskLabel = FileSearchTextField(labelWithString: "File mask:")
	private let escapeButton = DesktopKeycapButton(
		title: "Esc",
		target: nil,
		action: nil
	)
	private let keyboardHints = FileSearchKeyboardHintsView()
	private let table = FileSearchResultsTableView()
	private var sheet: NSWindow?
	private var previousResponder: NSResponder?
	private var appearanceBinding: DesktopPanelAppearanceBinding?
	private var filenameRows: [FileLocation] = []
	private var contentRows: [FileViewerSearchResult] = []
	private var activeRoot: String?
	private var submittedQuery = ""
	private var submittedMask: String?
	private var awaitingCurrentResults = false

	init(mode: Mode)
	{
		self.mode = mode
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView()
	{
		queryField.delegate = self
		maskField.delegate = self
		escapeButton.target = self
		escapeButton.action = #selector(dismissFromButton)
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(chooseSelected)
		table.onNavigate =
		{
			[weak self] direction in self?.moveSelection(direction)
		}
		table.onAccept =
		{
			[weak self] in self?.chooseSelected()
		}
		table.onCancel =
		{
			[weak self] in self?.dismiss()
		}
		view = DesktopFileSearchContentView(
			mode: mode,
			queryField: queryField,
			maskField: maskField,
			maskLabel: maskLabel,
			escapeButton: escapeButton,
			keyboardHints: keyboardHints,
			table: table
		)
	}

	func present(in window: NSWindow)
	{
		if sheet != nil
		{
			focusSearch()
			return
		}
		_ = view
		previousResponder = window.firstResponder
		let presented = FileSearchSheetPanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		presented.contentViewController = self
		presented.onCancel =
		{
			[weak self] in self?.dismiss()
		}
		presented.title = mode == .filename ? "Quick Open" : "Search Files"
		presented.hasShadow = true
		presented.isFloatingPanel = true
		presented.isReleasedWhenClosed = false
		presented.delegate = self
		presented.setContentSize(DesktopFileSearchContentView.preferredSize(in: window))
		appearanceBinding = DesktopPanelAppearanceBinding(
			panel: presented,
			source: window.contentView ?? view
		)
		sheet = presented
		window.beginSheet(presented)
		{
			[weak self, weak presented] _ in
			guard let presented
			else
			{
				return
			}
			self?.finish(
				presented,
				endSheet: false
			)
		}
		focusSearch()
		if !queryField.stringValue.isEmpty
		{
			submitQuery()
		}
	}

	func focusSearch()
	{
		sheet?.makeFirstResponder(queryField)
	}

	func dismiss()
	{
		guard let sheet
		else
		{
			return
		}
		finish(
			sheet,
			endSheet: true
		)
	}

	@objc private func dismissFromButton()
	{
		dismiss()
	}

	func windowWillClose(_ notification: Notification)
	{
		guard let window = notification.object as? NSWindow
		else
		{
			return
		}
		finish(
			window,
			endSheet: true
		)
	}

	private func finish(
		_ window: NSWindow,
		endSheet: Bool
	)
	{
		guard sheet === window
		else
		{
			return
		}
		sheet = nil
		appearanceBinding?.invalidate()
		appearanceBinding = nil
		if endSheet, let parent = window.sheetParent
		{
			parent.endSheet(window)
			if let previousResponder = previousResponder as? NSView,
				previousResponder.window === parent
			{
				parent.makeFirstResponder(previousResponder)
			}
		}
		window.orderOut(nil)
		previousResponder = nil
		submittedQuery = ""
		submittedMask = nil
		awaitingCurrentResults = false
		onCancelSearch?()
		onDismiss?()
	}

	func render(_ state: FileViewerState)
	{
		if activeRoot != state.activeRoot
		{
			let hadRows = !filenameRows.isEmpty || !contentRows.isEmpty
			activeRoot = state.activeRoot
			filenameRows = []
			contentRows = []
			queryField.stringValue = ""
			submittedQuery = ""
			submittedMask = nil
			awaitingCurrentResults = false
			if hadRows
			{
				table.reloadData()
			}
		}
		guard sheet != nil, !submittedQuery.isEmpty
		else
		{
			return
		}
		let previousFilenames = filenameRows
		let previousContent = contentRows
		if state.searchRequest != nil
		{
			awaitingCurrentResults = false
			filenameRows = []
			contentRows = []
		}
		else if state.searchFailure != nil
		{
			filenameRows = []
			contentRows = []
		}
		else if mode == .filename, let page = state.filenameResults
		{
			filenameRows = page.results
		}
		else if mode == .content, let page = state.contentResults
		{
			contentRows = page.results
		}
		let changed = previousFilenames != filenameRows || previousContent != contentRows
		if changed
		{
			table.reloadData()
			if numberOfRows(in: table) > 0
			{
				table.selectRowIndexes(
					IndexSet(integer: 0),
					byExtendingSelection: false
				)
				table.scrollRowToVisible(0)
			}
		}
	}

	func controlTextDidChange(_ notification: Notification)
	{
		submitQuery()
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy selector: Selector
	) -> Bool
	{
		switch ViewerFileSearchSelection.command(for: selector)
		{
		case .navigate(let direction): moveSelection(direction)
		case .accept: chooseSelected()
		case .cancel: dismiss()
		case nil: return false
		}
		return true
	}

	private func submitQuery()
	{
		let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let mask = maskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let normalizedMask = mask.isEmpty ? nil : mask
		guard query != submittedQuery || normalizedMask != submittedMask
		else
		{
			return
		}
		let hadRows = !filenameRows.isEmpty || !contentRows.isEmpty
		submittedQuery = query
		submittedMask = normalizedMask
		awaitingCurrentResults = !query.isEmpty
		filenameRows = []
		contentRows = []
		if hadRows
		{
			table.reloadData()
		}
		if query.isEmpty
		{
			onCancelSearch?()
		}
		else
		{
			onQuery?(query, normalizedMask)
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		mode == .filename ? filenameRows.count : contentRows.count
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		if mode == .filename
		{
			let cell = NSTableCellView()
			let result = ViewerFileSearchResultView(relativePath: filenameRows[row].relativePath)
			result.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(result)
			NSLayoutConstraint.activate([
				result.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
				result.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
				result.topAnchor.constraint(equalTo: cell.topAnchor),
				result.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
			])
			cell.setAccessibilityLabel(filenameRows[row].relativePath)
			return cell
		}
		let content = contentRows[row]
		let cell = NSTableCellView()
		let result = FileSearchContentResultView(
			result: content,
			query: submittedQuery
		)
		result.setSelected(row == table.selectedRow)
		result.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(result)
		NSLayoutConstraint.activate([
			result.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
			result.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
			result.topAnchor.constraint(equalTo: cell.topAnchor),
			result.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
		])
		cell
			.setAccessibilityLabel(
				"\(content.lineText), \(content.location.relativePath):\(content.lineNumber)"
			)
		return cell
	}

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		FileSearchResultSelectionRow()
	}

	func tableViewSelectionDidChange(_ notification: Notification)
	{
		guard mode == .content
		else
		{
			return
		}
		for row in 0 ..< table.numberOfRows
		{
			guard let cell = table.view(
				atColumn: 0,
				row: row,
				makeIfNecessary: false
			) as? NSTableCellView,
				let result = cell.subviews.first as? FileSearchContentResultView
			else
			{
				continue
			}
			result.setSelected(row == table.selectedRow)
		}
	}

	private func moveSelection(_ direction: FileSearchResultsTableView.Direction)
	{
		guard let next = ViewerFileSearchSelection.next(
			current: table.selectedRow,
			count: numberOfRows(in: table),
			direction: direction
		)
		else
		{
			return
		}
		table.selectRowIndexes(
			IndexSet(integer: next),
			byExtendingSelection: false
		)
		table.scrollRowToVisible(next)
	}

	@objc private func chooseSelected()
	{
		let row = table.selectedRow
		guard row >= 0, !awaitingCurrentResults
		else
		{
			return
		}
		if mode == .filename, filenameRows.indices.contains(row)
		{
			onChooseFilename?(filenameRows[row])
		}
		else if mode == .content, contentRows.indices.contains(row)
		{
			onChooseContent?(contentRows[row])
		}
		dismiss()
	}
}

@MainActor
private final class FileSearchSheetPanel: NSPanel
{
	var onCancel: (() -> Void)?

	override var canBecomeKey: Bool
	{
		true
	}

	override func cancelOperation(_ sender: Any?)
	{
		onCancel?()
	}
}

@MainActor
final class FileSearchResultsTableView: NSTableView
{
	typealias Direction = ViewerFileSearchSelection.Direction
	var onNavigate: ((Direction) -> Void)?
	var onAccept: (() -> Void)?
	var onCancel: (() -> Void)?

	override func keyDown(with event: NSEvent)
	{
		switch ViewerFileSearchSelection.command(forKeyCode: event.keyCode)
		{
		case .navigate(let direction): onNavigate?(direction)
		case .accept: onAccept?()
		case .cancel: onCancel?()
		case nil: super.keyDown(with: event)
		}
	}
}
