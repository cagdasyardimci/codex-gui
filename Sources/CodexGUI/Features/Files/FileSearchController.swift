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
	private let queryField = NSTextField()
	private let maskField = NSTextField()
	private let maskLabel = NSTextField(labelWithString: "File mask:")
	private let escapeButton = NSButton(
		title: "Esc",
		target: nil,
		action: nil
	)
	private let statusLabel = NSTextField(labelWithString: "")
	private let hintsLabel = NSTextField(labelWithString: "↑ ↓  navigate     ↵  open")
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
		let container = FileSearchPanelBackgroundView()
		container.wantsLayer = true
		container.layer?.cornerRadius = 16
		container.layer?.masksToBounds = true
		container.refreshBackground()
		queryField.placeholderString = mode == .filename
			? "Open file by name" : "Search file contents"
		queryField.setAccessibilityLabel(queryField.placeholderString ?? "Search files")
		queryField.delegate = self
		queryField.isBordered = false
		queryField.drawsBackground = false
		queryField.focusRingType = .none
		queryField.font = .systemFont(ofSize: 15)
		maskField.placeholderString = "*.swift,*.md"
		maskField.setAccessibilityLabel("File mask")
		maskField.delegate = self
		maskField.font = .systemFont(ofSize: 13)
		maskField.bezelStyle = .roundedBezel
		maskLabel.textColor = .secondaryLabelColor
		maskLabel.font = .systemFont(ofSize: 13)
		escapeButton.target = self
		escapeButton.action = #selector(dismissFromButton)
		escapeButton.bezelStyle = .rounded
		escapeButton.setAccessibilityLabel("Close search")
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.font = .systemFont(ofSize: 12)
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setAccessibilityLabel("Search status")
		hintsLabel.textColor = .secondaryLabelColor
		hintsLabel.font = .systemFont(ofSize: 12)

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
		column.resizingMask = .autoresizingMask
		table.addTableColumn(column)
		table.style = .plain
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.headerView = nil
		table.rowHeight = mode == .content ? 28 : 34
		table.intercellSpacing = NSSize(
			width: 0,
			height: 0
		)
		table.selectionHighlightStyle = .regular
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
		let header = NSView()
		let footer = NSView()
		let divider = NSBox()
		divider.boxType = .separator
		for item in [header, scroll, footer]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(item)
		}
		for item in [queryField, maskLabel, maskField, escapeButton]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(item)
		}
		for item in [divider, statusLabel, hintsLabel]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			footer.addSubview(item)
		}
		maskLabel.isHidden = mode == .filename
		maskField.isHidden = mode == .filename
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: container.topAnchor),
			header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			header.heightAnchor.constraint(equalToConstant: 54),
			scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
			scroll.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 10
			),
			scroll.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -10
			),
			footer.topAnchor.constraint(equalTo: scroll.bottomAnchor),
			footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			footer.heightAnchor.constraint(equalToConstant: 38),
			queryField.leadingAnchor.constraint(
				equalTo: header.leadingAnchor,
				constant: 22
			),
			queryField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			queryField.heightAnchor.constraint(equalToConstant: 26),
			maskLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			maskField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			maskField.widthAnchor.constraint(equalToConstant: 112),
			maskField.heightAnchor.constraint(equalToConstant: 26),
			escapeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			escapeButton.trailingAnchor.constraint(
				equalTo: header.trailingAnchor,
				constant: -14
			),
			escapeButton.widthAnchor.constraint(equalToConstant: 42),
			divider.topAnchor.constraint(equalTo: footer.topAnchor),
			divider.leadingAnchor.constraint(
				equalTo: footer.leadingAnchor,
				constant: 10
			),
			divider.trailingAnchor.constraint(
				equalTo: footer.trailingAnchor,
				constant: -10
			),
			statusLabel.leadingAnchor.constraint(
				equalTo: footer.leadingAnchor,
				constant: 16
			),
			statusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			hintsLabel.trailingAnchor.constraint(
				equalTo: footer.trailingAnchor,
				constant: -16
			),
			hintsLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			statusLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: hintsLabel.leadingAnchor,
				constant: -8
			),
		])
		if mode == .content
		{
			NSLayoutConstraint.activate([
				queryField.trailingAnchor.constraint(
					equalTo: maskLabel.leadingAnchor,
					constant: -12
				),
				maskLabel.trailingAnchor.constraint(
					equalTo: maskField.leadingAnchor,
					constant: -8
				),
				maskField.trailingAnchor.constraint(
					equalTo: escapeButton.leadingAnchor,
					constant: -8
				),
			])
		}
		else
		{
			queryField.trailingAnchor.constraint(
				equalTo: escapeButton.leadingAnchor,
				constant: -8
			)
			.isActive = true
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
		presented.setContentSize(NSSize(
			width: min(
				mode == .content ? 768 : 640,
				max(
					400,
					window.frame.width - 80
				)
			),
			height: mode == .content ? 500 : 410
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
			statusLabel.stringValue = "Enter a query"
			return
		}
		let previousFilenames = filenameRows
		let previousContent = contentRows
		if state.searchRequest != nil
		{
			awaitingCurrentResults = false
			filenameRows = []
			contentRows = []
			statusLabel.stringValue = "Searching…"
		}
		else if awaitingCurrentResults
		{
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
				unit: page.results.count == 1 ? "file" : "files",
				truncated: page.isTruncated
			)
			statusLabel.toolTip = excludedDirectoryTip(page.excludedDirectoryCount)
		}
		else if mode == .content, let page = state.contentResults
		{
			contentRows = page.results
			statusLabel.stringValue = summary(
				count: page.results.count,
				empty: "No matching content",
				unit: page.results.count == 1 ? "matching line" : "matching lines",
				truncated: page.isTruncated
			)
			statusLabel.toolTip = excludedDirectoryTip(page.excludedDirectoryCount)
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
		truncated: Bool
	) -> String
	{
		if count == 0
		{
			return truncated ? "Search incomplete · no matches" : empty
		}
		return truncated
			? "Showing first \(count) \(unit)"
			: "\(count) \(unit)"
	}

	private func excludedDirectoryTip(_ count: Int) -> String?
	{
		count > 0 ? "\(count) generated folders skipped" : nil
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
		statusLabel.stringValue = query.isEmpty ? "Enter a query" : "Searching…"
		statusLabel.toolTip = nil
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
private final class FileSearchPanelBackgroundView: NSView
{
	func refreshBackground()
	{
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			.textBackgroundColor,
			for: self
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshBackground()
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
