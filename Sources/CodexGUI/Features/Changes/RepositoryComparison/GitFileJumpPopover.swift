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
	private let search = NSSearchField()
	private let results = NSStackView()
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
		let root = DesktopSurface(AppKitColorTokens.elevated)
		view = root
		search.placeholderString = "Jump to file…"
		search.setAccessibilityLabel("Search changed files")
		search.delegate = self
		search.target = self
		search.action = #selector(chooseFirst)
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
		let layout = NSStackView(views: [search, scroll])
		layout.orientation = .vertical
		layout.alignment = .leading
		layout.spacing = 8
		AppKitLayout.pin(
			layout,
			to: root,
			inset: 8
		)
		NSLayoutConstraint.activate([
			search.widthAnchor.constraint(equalTo: layout.widthAnchor),
			scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
		])
		reloadResults()
	}

	func focusSearch()
	{
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
		switch commandSelector
		{
		case #selector(NSResponder.moveDown(_:)):
			selectedIndex = min(
				selectedIndex + 1,
				max(
					0,
					visibleEntries.count - 1
				)
			)
			updateSelection()
			return true
		case #selector(NSResponder.moveUp(_:)):
			selectedIndex = max(
				0,
				selectedIndex - 1
			)
			updateSelection()
			return true
		case #selector(NSResponder.insertNewline(_:)):
			chooseFirst()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			onCancel?()
			return true
		default:
			return false
		}
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
				button.heightAnchor.constraint(equalToConstant: 30),
			])
		}
		updateSelection()
		if matches.isEmpty || matches.count > Self.maximumVisibleResultCount
		{
			let message = matches.isEmpty ? "No matching files" : "Refine search to see more files"
			let label = NSTextField(labelWithString: message)
			label.textColor = .secondaryLabelColor
			results.addArrangedSubview(label)
		}
	}

	private func makeResultButton(_ entry: GitFileJumpIndex.Entry) -> DesktopLayerButton
	{
		let button = DesktopLayerButton(
			title: "",
			target: self,
			action: #selector(choose(_:))
		)
		button.isBordered = false
		button.alignment = .left
		button.identifier = NSUserInterfaceItemIdentifier(entry.id)
		button.setAccessibilityLabel(entry.path)
		button.toolTip = entry.path
		let title = NSMutableAttributedString(
			string: entry.filename,
			attributes: [
				.font: NSFont.systemFont(
					ofSize: 13,
					weight: .medium
				),
				.foregroundColor: NSColor.labelColor,
			]
		)
		title.append(NSAttributedString(
			string: "    " + (entry.directory.isEmpty ? "Top level" : entry.directory),
			attributes: [
				.font: NSFont.systemFont(ofSize: 11),
				.foregroundColor: NSColor.secondaryLabelColor,
			]
		))
		button.attributedTitle = title
		button.cell?.lineBreakMode = .byTruncatingMiddle
		button.wantsLayer = true
		return button
	}

	private func updateSelection()
	{
		for (index, button) in resultButtons.enumerated()
		{
			button.layerBackgroundAlpha = index == selectedIndex ? 0.18 : nil
			button.layerBackgroundColor = index == selectedIndex
				? .selectedContentBackgroundColor : .clear
		}
		if resultButtons.indices.contains(selectedIndex)
		{
			let button = resultButtons[selectedIndex]
			button.scrollToVisible(button.bounds)
		}
	}
}
