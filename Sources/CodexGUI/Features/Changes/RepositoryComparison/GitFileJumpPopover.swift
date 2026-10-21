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
	private let search = ViewerSearchField()
	private let results = FileJumpResultsStack()
	private var visibleEntries: [GitFileJumpIndex.Entry] = []
	private var resultButtons: [DesktopLayerButton] = []
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
		let root = DesktopSurface(AppKitColorTokens.searchPanel)
		view = root
		search.placeholderString = "Jump to file"
		search.drawsSurface = false
		(search.cell as? NSSearchFieldCell)?.searchButtonCell = nil
		search.isBordered = false
		search.drawsBackground = false
		search.focusRingType = .none
		search.font = .systemFont(ofSize: 14)
		search.sendsSearchStringImmediately = true
		search.setAccessibilityLabel("Search changed files")
		search.delegate = self
		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		results.orientation = .vertical
		results.alignment = .leading
		results.spacing = 0
		results.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = results
		results.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
		let icon = NSImageView(image: DesktopIcons.image(.search))
		icon.contentTintColor = .secondaryLabelColor
		icon.imageScaling = .scaleProportionallyDown
		icon.setAccessibilityElement(false)
		let header = AppKitLayout.horizontalStack(
			[icon, search],
			spacing: 8
		)
		let layout = NSStackView(views: [header, scroll])
		layout.orientation = .vertical
		layout.alignment = .leading
		layout.spacing = 8
		AppKitLayout.pin(
			layout,
			to: root,
			inset: 8
		)
		NSLayoutConstraint.activate([
			header.widthAnchor.constraint(equalTo: layout.widthAnchor),
			header.heightAnchor.constraint(equalToConstant: 32),
			icon.widthAnchor.constraint(equalToConstant: 16),
			icon.heightAnchor.constraint(equalToConstant: 16),
			search.heightAnchor.constraint(equalToConstant: 20),
			scroll.bottomAnchor.constraint(equalTo: layout.bottomAnchor),
			scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
		])
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
		if matches.isEmpty || matches.count > Self.maximumVisibleResultCount
		{
			let message = matches.isEmpty ? "No matching files" : "Refine search to see more files"
			let label = NSTextField(labelWithString: message)
			label.textColor = .secondaryLabelColor
			results.addArrangedSubview(label)
		}
		view.layoutSubtreeIfNeeded()
		updateSelection()
	}

	private func makeResultButton(_ entry: GitFileJumpIndex.Entry) -> DesktopLayerButton
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
			button.layerBackgroundAlpha = nil
			button.layerBackgroundColor = index == selectedIndex
				? AppKitColorTokens.searchResultSelection : .clear
		}
		if resultButtons.indices.contains(selectedIndex)
		{
			let button = resultButtons[selectedIndex]
			button.scrollToVisible(button.bounds)
		}
	}
}

@MainActor
private final class FileJumpResultsStack: NSStackView
{
	override var isFlipped: Bool
	{
		true
	}
}
