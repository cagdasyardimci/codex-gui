import AppKit

@MainActor
final class ChatSearchController: NSViewController
{
	struct Entry: Equatable
	{
		let thread: ThreadSummary
		let context: String
	}

	var onChoose: ((ThreadSummary) -> Void)?
	var onNewChat: (() -> Void)?
	var onCancel: (() -> Void)?
	private let search: NSSearchField
	private let rows = NSStackView()
	private var scroll: NSScrollView?
	private var buttons: [DesktopSearchResultButton] = []
	private var entries: [Entry] = []
	private var selectedIndex = 0
	private var canCreateChat = false
	private var renderedQuery: String?

	init(searchField: NSSearchField)
	{
		search = searchField
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
		view = DesktopSurface(AppKitColorTokens.searchPanel)
		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = 0
		let scroll = AppKitLayout.scrollableContent(
			rows,
			inset: 0
		)
		self.scroll = scroll
		scroll.drawsBackground = false
		let layout = AppKitLayout.verticalStack(
			[search, scroll],
			spacing: 12
		)
		AppKitLayout.pin(
			layout,
			to: view,
			inset: 12
		)
		NSLayoutConstraint.activate([
			search.widthAnchor.constraint(equalTo: layout.widthAnchor),
			search.heightAnchor.constraint(equalToConstant: 32),
			scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
			scroll.bottomAnchor.constraint(equalTo: layout.bottomAnchor),
		])
	}

	func render(
		entries: [Entry],
		canCreateChat: Bool
	)
	{
		_ = view
		let visibleEntries = Array(entries.prefix(200))
		guard visibleEntries != self.entries || canCreateChat != self.canCreateChat
			|| renderedQuery != search.stringValue
		else
		{
			return
		}
		renderedQuery = search.stringValue
		self.entries = visibleEntries
		self.canCreateChat = canCreateChat
		selectedIndex = 0
		buttons.removeAll()
		for row in rows.arrangedSubviews
		{
			rows.removeArrangedSubview(row)
			row.removeFromSuperview()
		}
		addHeading("Chats")
		for (index, entry) in self.entries.enumerated()
		{
			addResult(
				title: entry.thread.name ?? entry.thread.preview ?? "Untitled chat",
				context: entry.context,
				shortcut: index < 9 ? "⌃\(index + 1)" : ""
			)
		}
		if entries.isEmpty
		{
			addHeading("No matching conversations")
		}
		if entries.count > 200
		{
			addHeading("Refine search to see more chats")
		}
		if canCreateChat
		{
			addHeading("Quick actions")
			addResult(
				title: "New chat",
				context: "",
				shortcut: "⌘N"
			)
		}
		view.layoutSubtreeIfNeeded()
		updateSelection()
	}

	func revealSelection()
	{
		view.layoutSubtreeIfNeeded()
		updateSelection()
	}

	func handle(_ selector: Selector) -> Bool
	{
		switch ViewerFileSearchSelection.command(for: selector)
		{
		case .navigate(let direction):
			if let next = ViewerFileSearchSelection.next(
				current: selectedIndex,
				count: buttons.count,
				direction: direction
			)
			{
				selectedIndex = next
				updateSelection()
			}
		case .accept: chooseIndex(selectedIndex)
		case .cancel: onCancel?()
		case nil: return false
		}
		return true
	}

	func handleKeyEquivalent(_ event: NSEvent) -> Bool
	{
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if modifiers == .control, let text = event.charactersIgnoringModifiers,
			let digit = Int(text), (1 ... 9).contains(digit), digit <= entries.count
		{
			chooseIndex(digit - 1)
			return true
		}
		if modifiers == .command, event.charactersIgnoringModifiers == "n", canCreateChat
		{
			onNewChat?()
			return true
		}
		return false
	}

	private func addHeading(_ text: String)
	{
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: 12)
		label.textColor = .secondaryLabelColor
		let container = NSView()
		AppKitLayout.pin(
			label,
			to: container,
			inset: 8
		)
		rows.addArrangedSubview(container)
		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(equalTo: rows.widthAnchor),
			container.heightAnchor.constraint(equalToConstant: 32),
		])
	}

	private func addResult(
		title: String,
		context: String,
		shortcut: String
	)
	{
		let button = DesktopSearchResultButton(
			title: title,
			context: context,
			shortcut: shortcut,
			target: self,
			action: #selector(choose(_:))
		)
		button.tag = buttons.count
		rows.addArrangedSubview(button)
		buttons.append(button)
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalTo: rows.widthAnchor),
			button.heightAnchor.constraint(equalToConstant: 32),
		])
	}

	@objc private func choose(_ sender: NSButton)
	{
		chooseIndex(sender.tag)
	}

	private func chooseIndex(_ index: Int)
	{
		if entries.indices.contains(index)
		{
			onChoose?(entries[index].thread)
		}
		else if canCreateChat, index == entries.count
		{
			onNewChat?()
		}
	}

	private func updateSelection()
	{
		for (index, button) in buttons.enumerated()
		{
			button.layerBackgroundColor = index == selectedIndex
				? AppKitColorTokens.searchResultSelection : .clear
			button.layerBackgroundAlpha = nil
			button.layer?.cornerRadius = 12
		}
		if selectedIndex == 0, let scroll
		{
			scroll.contentView.scroll(to: .zero)
			scroll.reflectScrolledClipView(scroll.contentView)
		}
		else if buttons.indices.contains(selectedIndex)
		{
			buttons[selectedIndex].scrollToVisible(buttons[selectedIndex].bounds)
		}
	}
}
