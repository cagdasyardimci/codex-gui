import AppKit

struct GitFileJumpIndex
{
	struct Entry: Equatable
	{
		let id: String
		let filename: String
		let directory: String

		var path: String
		{
			directory.isEmpty ? filename : directory + "/" + filename
		}
	}

	let entries: [Entry]

	init(files: [GitComparisonFile])
	{
		entries = files.map
		{
			file in
			let path = file.path as NSString
			let directory = path.deletingLastPathComponent
			return Entry(
				id: file.id,
				filename: path.lastPathComponent,
				directory: directory == "." ? "" : directory
			)
		}
	}

	func matches(_ query: String) -> [Entry]
	{
		let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty
		else
		{
			return entries
		}
		return entries.filter
		{
			$0.path.localizedCaseInsensitiveContains(text)
		}
	}
}

@MainActor
final class GitFileJumpPopoverController: NSViewController, NSSearchFieldDelegate
{
	var onSelect: ((String) -> Void)?
	var onCancel: (() -> Void)?
	private static let maximumVisibleResultCount = 200

	private let index: GitFileJumpIndex
	private let search = DesktopSearchField(presentation: .viewerOverlay)
	private let results = DesktopFlippedStackView()
	private var visibleEntries: [GitFileJumpIndex.Entry] = []
	private var resultButtons: [DesktopSearchResultButton] = []
	private var selectedIndex = 0

	init(index: GitFileJumpIndex)
	{
		self.index = index
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		search.configureSearch(
			placeholder: "Jump to file",
			accessibilityLabel: "Search changed files",
			delegate: self,
			sendsImmediately: true
		)
		view = DesktopSearchOverlayView(
			presentation: .changedFiles,
			search: search,
			results: results
		)
		reloadResults()
	}

	func focusSearch()
	{
		view.layoutSubtreeIfNeeded()
		updateSelection()
		view.window?.makeFirstResponder(search)
	}

	func controlTextDidChange(_ notification: Notification)
	{
		guard notification.object as? NSSearchField === search
		else
		{
			return
		}
		reloadResults()
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		switch ViewerFileSearchSelection.command(for: commandSelector)
		{
		case .navigate(let direction): moveSelection(direction)
		case .accept: chooseFirst()
		case .cancel: onCancel?()
		case nil: return false
		}
		return true
	}

	@objc private func chooseFirst()
	{
		if visibleEntries.indices.contains(selectedIndex)
		{
			onSelect?(visibleEntries[selectedIndex].id)
		}
	}

	@objc private func choose(_ sender: NSButton)
	{
		if let id = sender.identifier?.rawValue
		{
			onSelect?(id)
		}
	}

	private func reloadResults()
	{
		resultButtons.removeAll()
		selectedIndex = 0
		for view in results.arrangedSubviews
		{
			results.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		let matches = index.matches(search.stringValue)
		visibleEntries = Array(matches.prefix(Self.maximumVisibleResultCount))
		for entry in visibleEntries
		{
			let button = makeResultButton(entry)
			results.addArrangedSubview(button)
			resultButtons.append(button)
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalTo: results.widthAnchor),
				button.heightAnchor.constraint(equalToConstant: 32),
			])
		}
		view.layoutSubtreeIfNeeded()
		updateSelection()
	}

	private func makeResultButton(_ entry: GitFileJumpIndex.Entry) -> DesktopSearchResultButton
	{
		let button = DesktopSearchResultButton(
			title: entry.filename,
			context: entry.directory,
			inlineContext: true,
			target: self,
			action: #selector(choose(_:))
		)
		button.identifier = NSUserInterfaceItemIdentifier(entry.id)
		button.setAccessibilityLabel(entry.path)
		button.toolTip = entry.path
		button.layer?.cornerRadius = 12
		button.wantsLayer = true
		return button
	}

	private func moveSelection(_ direction: ViewerFileSearchSelection.Direction)
	{
		guard let next = ViewerFileSearchSelection.next(
			current: selectedIndex,
			count: visibleEntries.count,
			direction: direction
		)
		else
		{
			return
		}
		selectedIndex = next
		updateSelection()
	}

	private func updateSelection()
	{
		for (index, button) in resultButtons.enumerated()
		{
			button.setSelected(index == selectedIndex)
		}
		if resultButtons.indices.contains(selectedIndex)
		{
			let button = resultButtons[selectedIndex]
			button.scrollToVisible(button.bounds)
		}
	}
}
