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
final class FileSearchPanel: NSViewController, NSSearchFieldDelegate,
	NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate
{
	enum Mode
	{
		case filename, content
	}
	var onQuery: ((String, String?) -> Void)?
	var onChooseFilename: ((FileLocation) -> Void)?
	var onChooseContent: ((FileViewerSearchResult) -> Void)?
	var onDismiss: (() -> Void)?
	var onCancelSearch: (() -> Void)?

	private let mode: Mode
	private let queryField = ViewerSearchField()
	private let maskField = NSTextField()
	private let statusLabel = NSTextField(labelWithString: "")
	private let table = FileSearchResultsTableView()
	private var sheet: NSWindow?
	private var previousResponder: NSResponder?
	private var appearanceBinding: DesktopPanelAppearanceBinding?
	private var filenameRows: [FileLocation] = []
	private var contentRows: [FileViewerSearchResult] = []
	private var activeRoot: String?
	private var submittedQuery = ""

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
		let container = NSView()
		if mode == .filename
		{
			queryField.placeholderString = "Open file by name"
		}
		else
		{
			queryField.placeholderString = "Search file contents"
		}
		queryField.setAccessibilityLabel(queryField.placeholderString ?? "Search files")
		queryField.delegate = self
		queryField.sendsSearchStringImmediately = true
		maskField.placeholderString = "File mask, e.g. *.swift,*.md"
		maskField.setAccessibilityLabel("File mask")
		maskField.delegate = self
		maskField.isHidden = mode == .filename
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.setAccessibilityLabel("Search status")

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
		table.addTableColumn(column)
		table.headerView = nil
		table.rowHeight = mode == .content ? 46 : 34
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(chooseSelected)
		table.setAccessibilityLabel("File search results")
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
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		var fields: [NSView] = [queryField]
		if mode == .content
		{
			fields.append(maskField)
		}
		fields.append(contentsOf: [statusLabel, scroll])
		let stack = NSStackView(views: fields)
		stack.orientation = .vertical
		stack.alignment = .width
		stack.spacing = 10
		stack.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 16
			),
			stack.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 16
			),
			stack.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -16
			),
			stack.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -16
			),
			queryField.widthAnchor.constraint(equalTo: stack.widthAnchor),
			statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
			scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
			scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
		])
		if mode == .content
		{
			maskField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		view = container
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
		let presented = NSPanel(
			contentRect: .zero,
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		presented.contentViewController = self
		presented.title = mode == .filename ? "Quick Open" : "Search Files"
		presented.isReleasedWhenClosed = false
		presented.delegate = self
		presented.setContentSize(NSSize(
			width: min(
				640,
				max(
					400,
					window.frame.width - 80
				)
			),
			height: mode == .content ? 410 : 380
		))
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
		onCancelSearch?()
		onDismiss?()
	}

	func render(_ state: FileViewerState)
	{
		if activeRoot != state.activeRoot
		{
			activeRoot = state.activeRoot
			filenameRows = []
			contentRows = []
			queryField.stringValue = ""
			submittedQuery = ""
		}
		guard sheet != nil, !submittedQuery.isEmpty
		else
		{
			statusLabel.stringValue = "Enter a query"
			table.reloadData()
			return
		}
		let previousFilenames = filenameRows
		let previousContent = contentRows
		if state.searchRequest != nil
		{
			filenameRows = []
			contentRows = []
			statusLabel.stringValue = "Searching…"
		}
		else if let failure = state.searchFailure
		{
			filenameRows = []
			contentRows = []
			statusLabel.stringValue = "Search failed: \(failure)"
		}
		else if mode == .filename, let page = state.filenameResults
		{
			filenameRows = page.results
			statusLabel.stringValue = summary(
				count: page.results.count,
				empty: "No matching files",
				unit: "files",
				truncated: page.isTruncated,
				excluded: page.excludedDirectoryCount
			)
		}
		else if mode == .content, let page = state.contentResults
		{
			contentRows = page.results
			statusLabel.stringValue = summary(
				count: page.results.count,
				empty: "No matching content",
				unit: "matches",
				truncated: page.isTruncated,
				excluded: page.excludedDirectoryCount
			)
		}
		else
		{
			statusLabel.stringValue = submittedQuery.isEmpty ? "Enter a query" : "Searching…"
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

	private func summary(
		count: Int,
		empty: String,
		unit: String,
		truncated: Bool,
		excluded: Int
	) -> String
	{
		var text = count == 0 ? empty : (truncated
			? "Showing first \(count) \(unit)"
			: "\(count) \(unit)")
		if excluded > 0
		{
			text += " · \(excluded) generated folders skipped"
		}
		return text
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
		submittedQuery = query
		filenameRows = []
		contentRows = []
		table.reloadData()
		statusLabel.stringValue = query.isEmpty ? "Enter a query" : "Searching…"
		if query.isEmpty
		{
			onCancelSearch?()
		}
		else
		{
			onQuery?(query, mask.isEmpty ? nil : mask)
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
		let location = content.location
		let name = URL(fileURLWithPath: location.relativePath).lastPathComponent
		let detail = "\(location.relativePath):\(content.lineNumber)  \(content.lineText)"
		let cell = NSTableCellView()
		let title = NSTextField(labelWithString: name)
		title.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
		title.lineBreakMode = .byTruncatingMiddle
		let subtitle = NSTextField(labelWithString: detail)
		subtitle.textColor = .secondaryLabelColor
		subtitle.font = .systemFont(ofSize: 11)
		subtitle.lineBreakMode = .byTruncatingTail
		let stack = NSStackView(views: [title, subtitle])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 1
		stack.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor,
				constant: 8
			),
			stack.trailingAnchor.constraint(
				lessThanOrEqualTo: cell.trailingAnchor,
				constant: -8
			),
			stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		cell.setAccessibilityLabel(detail)
		return cell
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
		guard row >= 0
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
