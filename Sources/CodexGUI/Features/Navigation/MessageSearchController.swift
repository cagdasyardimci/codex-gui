import AppKit

@MainActor
final class MessageSearchController: NSViewController, NSSearchFieldDelegate,
	NSTableViewDataSource, NSTableViewDelegate
{
	var onSearch: ((String) -> Void)?
	var onOpenHit: ((MessageSearchHit) -> Void)?
	var onLoadMore: (() -> Void)?

	private let searchField = NSSearchField()
	private let scopeLabel = NSTextField(wrappingLabelWithString: "")
	private let loadingLabel = NSTextField(labelWithString: "")
	private let tableView = NSTableView()
	private let loadMoreButton = NSButton(
		title: "Load More History",
		target: nil,
		action: nil
	)
	private let closeButton = NSButton(
		title: "Close",
		target: nil,
		action: nil
	)
	private var results: MessageSearchResults?

	override func loadView()
	{
		let container = NSView()
		configureSearchFields()
		let scrollView = makeResultsScrollView()
		configureSearchActions()

		let stack = AppKitLayout.verticalStack([
			AppKitLayout.title("Search Messages"),
			searchField,
			scopeLabel,
			loadingLabel,
			scrollView,
			loadMoreButton,
			closeButton,
		])
		AppKitLayout.pin(
			stack,
			to: container
		)
		searchField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scopeLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
		view = container
	}

	private func configureSearchFields()
	{
		searchField.placeholderString = "Search message contents"
		searchField.setAccessibilityLabel("Search loaded message contents")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true

		scopeLabel.textColor = .secondaryLabelColor
		scopeLabel.font = .systemFont(ofSize: 11)
		scopeLabel.setAccessibilityLabel("Message search scope and history limits")

		loadingLabel.textColor = .secondaryLabelColor
		loadingLabel.setAccessibilityLabel("Message history loading status")
	}

	private func makeResultsScrollView() -> NSScrollView
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("messageHit"))
		tableView.addTableColumn(column)
		tableView.headerView = nil
		tableView.rowHeight = 54
		tableView.delegate = self
		tableView.dataSource = self
		tableView.target = self
		tableView.doubleAction = #selector(openSelected)
		tableView.setAccessibilityLabel("Matching messages")

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		return scrollView
	}

	private func configureSearchActions()
	{
		loadMoreButton.target = self
		loadMoreButton.action = #selector(loadMore)
		loadMoreButton.setAccessibilityLabel("Load more conversation history into message search")

		closeButton.target = self
		closeButton.action = #selector(close)
		closeButton.setAccessibilityLabel("Close message search")
	}

	func present(in window: NSWindow)
	{
		let sheet = NSWindow(contentViewController: self)
		sheet.title = "Search Messages"
		sheet.setContentSize(NSSize(
			width: min(
				680,
				max(
					440,
					window.frame.width - 80
				)
			),
			height: 480
		))
		window.beginSheet(sheet)
		sheet.makeFirstResponder(searchField)
		onSearch?(searchField.stringValue)
	}

	func render(
		_ results: MessageSearchResults?,
		loading: Bool,
		unavailableReason: String?
	)
	{
		self.results = results
		if let scope = results?.scope
		{
			scopeLabel.stringValue =
				scope.description
					+ (scope.isComplete
						? "" : ". Load more history to expand search.")
		}
		else
		{
			scopeLabel.stringValue = "Search covers message history loaded into this app."
		}
		loadingLabel.stringValue =
			unavailableReason
				?? (loading ? "Loading message history…" : "")
		loadingLabel.isHidden = loadingLabel.stringValue.isEmpty
		loadMoreButton.isHidden = results?.scope.canLoadMore != true
		loadMoreButton.isEnabled = !loading
		tableView.reloadData()
	}

	func controlTextDidChange(_ notification: Notification)
	{
		onSearch?(searchField.stringValue)
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy selector: Selector
	) -> Bool
	{
		if selector == #selector(NSResponder.cancelOperation(_:))
		{
			close()
			return true
		}
		return false
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		results?.hits.count ?? 0
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard let hit = results?.hits[row]
		else
		{
			return nil
		}
		let cell = NSTableCellView()
		let title = NSTextField(labelWithString: "\(hit.threadTitle) · \(hit.itemType)")
		title.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
		title.lineBreakMode = .byTruncatingTail

		let snippet = NSTextField(labelWithString: hit.snippet)
		snippet.textColor = .secondaryLabelColor
		snippet.lineBreakMode = .byTruncatingTail

		let stack = AppKitLayout.verticalStack(
			[title, snippet],
			spacing: 2
		)
		AppKitLayout.pin(
			stack,
			to: cell,
			inset: 4
		)
		cell.setAccessibilityLabel("\(hit.threadTitle), \(hit.itemType), \(hit.snippet)")
		return cell
	}

	@objc private func openSelected()
	{
		guard let results, results.hits.indices.contains(tableView.selectedRow)
		else
		{
			return
		}
		let hit = results.hits[tableView.selectedRow]
		if let sheet = view.window, let parent = sheet.sheetParent
		{
			parent.endSheet(sheet)
		}
		onOpenHit?(hit)
	}

	@objc private func loadMore()
	{
		onLoadMore?()
	}

	@objc private func close()
	{
		if let sheet = view.window, let parent = sheet.sheetParent
		{
			parent.endSheet(sheet)
		}
	}
}
