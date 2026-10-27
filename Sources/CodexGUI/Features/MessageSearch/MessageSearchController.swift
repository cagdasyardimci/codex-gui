import AppKit

@MainActor
final class MessageSearchController: NSViewController, NSSearchFieldDelegate,
	NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate
{
	var onSearch: ((String) -> Void)?
	var onOpenHit: ((MessageSearchHit) -> Void)?
	var onLoadMore: (() -> Void)?
	var onDismiss: (() -> Void)?

	private let searchView = DesktopSearchSheetView(presentation: .messages)
	private var searchField: DesktopSearchField
	{
		searchView.query
	}
	private var tableView: NSTableView
	{
		searchView.table
	}
	private var results: MessageSearchResults?
	private var presentedSheet: NSWindow?

	override func loadView()
	{
		configureSearchFields()
		tableView.delegate = self
		tableView.dataSource = self
		tableView.target = self
		tableView.doubleAction = #selector(openSelected)
		searchView.onLoadMore =
		{
			[weak self] in self?.onLoadMore?()
		}
		searchView.onClose =
		{
			[weak self] in self?.dismiss()
		}
		view = searchView
	}

	private func configureSearchFields()
	{
		searchField.configureSearch(
			placeholder: "Search message contents",
			accessibilityLabel: "Search loaded message contents",
			delegate: self,
			sendsImmediately: true
		)

	}

	func present(in window: NSWindow)
	{
		guard presentedSheet == nil
		else
		{
			presentedSheet?.makeFirstResponder(searchField)
			return
		}
		let sheet = NSWindow(contentViewController: self)
		sheet.delegate = self
		sheet.isReleasedWhenClosed = false
		sheet.title = "Search Messages"
		searchView.resize(
			window: sheet,
			relativeTo: window
		)
		presentedSheet = sheet
		window.beginSheet(sheet)
		{
			[weak self, weak sheet] _ in
			guard let sheet
			else
			{
				return
			}
			self?.finishSheetPresentation(
				sheet,
				endingSheet: false
			)
		}
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
		searchView.canLoadMore = results?.scope.canLoadMore == true
		searchView.isLoading = loading
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
		let content = DesktopSearchResultContentView(presentation: .message(
			title: "\(hit.threadTitle) · \(hit.itemType)",
			snippet: hit.snippet,
			accessibilityLabel: "\(hit.threadTitle), \(hit.itemType), \(hit.snippet)"
		))
		AppKitLayout.pin(
			content,
			to: cell,
			inset: 0
		)
		cell.setAccessibilityLabel(content.accessibilityLabel())
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
		let openHit = onOpenHit
		close()
		openHit?(hit)
	}

	@objc private func close()
	{
		dismiss()
	}

	func dismiss()
	{
		guard let sheet = presentedSheet
		else
		{
			return
		}
		finishSheetPresentation(
			sheet,
			endingSheet: true
		)
	}

	func windowWillClose(_ notification: Notification)
	{
		guard let sheet = notification.object as? NSWindow
		else
		{
			return
		}
		finishSheetPresentation(
			sheet,
			endingSheet: true
		)
	}

	private func finishSheetPresentation(
		_ sheet: NSWindow,
		endingSheet: Bool
	)
	{
		guard presentedSheet === sheet
		else
		{
			return
		}
		// A completion from a retired sheet must not dismiss its replacement owner's search.
		presentedSheet = nil
		let dismissed = onDismiss
		if endingSheet, let parent = sheet.sheetParent
		{
			parent.endSheet(sheet)
		}
		dismissed?()
	}
}
