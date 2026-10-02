import AppKit

@MainActor
final class ToolsTabViewController: NSViewController
{
	private enum Layout
	{
		static let headerHeight: CGFloat = 28
		static let tabHeight: CGFloat = 28
		static let tabWidth: CGFloat = 180
		static let tabSpacing: CGFloat = 4
		static let controlSize: CGFloat = 24
		static let controlSpacing: CGFloat = 4
		static let addButtonSpacing: CGFloat = 8
		static let contentInset: CGFloat = 20
		static let toolTileWidth: CGFloat = 240
	}

	var onCloseLastTab: (() -> Void)?
	var onClosePane: (() -> Void)?
	var onToggleExpanded: (() -> Void)?
	var onToggleSummary: (() -> Void)?
	var onTabSelectionChange: (() -> Void)?
	private(set) var tabCount = 0
	private(set) var selectedTabID: UUID?
	private(set) var isConversationSelected = false
	private var isExpanded = false
	private var conversationTitle = "New chat"
	private var tabIDs: [UUID] = []
	private let tabStack = NSStackView()
	private let tabScrollView = NSScrollView()
	private lazy var tabBar = makeTabHeader()
	private var preferredTabAreaWidth: NSLayoutConstraint?
	private var expandButton: NSButton?
	private var addTabButton: NSButton?
	private let summaryButton = PinnedSummaryToggleButton(
		title: "",
		target: nil,
		action: nil
	)

	var tabBarView: NSView
	{
		_ = view
		return tabBar
	}

	var minimumTabBarWidth: CGFloat
	{
		let trailingControlCount = summaryButton.isHidden ? 2 : 3
		return Layout.controlSize * CGFloat(trailingControlCount + 1)
			+ Layout.controlSpacing * CGFloat(trailingControlCount - 1)
			+ Layout.tabSpacing + Layout.addButtonSpacing
	}

	static func paneIcon() -> NSImage
	{
		let configuration = NSImage.SymbolConfiguration(
			pointSize: 16,
			weight: .regular
		)
		let image = NSImage(
			systemSymbolName: "rectangle.split.2x1",
			accessibilityDescription: nil
		)?.withSymbolConfiguration(configuration) ?? DesktopIcons.image(
			.sidebarRight,
			size: 16
		)
		image.isTemplate = true
		return image
	}

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		view = container

		_ = tabBar
		let toolsContent = makeToolsContent()
		toolsContent.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(toolsContent)

		NSLayoutConstraint.activate([
			toolsContent.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: Layout.contentInset
			),
			toolsContent.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -Layout.contentInset
			),
			toolsContent.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 32
			),
		])
		renderTabs()
	}

	func openNewTab()
	{
		let wasShowingConversation = isConversationSelected
		isConversationSelected = false
		let tabID = UUID()
		tabIDs.append(tabID)
		tabCount = tabIDs.count
		selectedTabID = tabID

		_ = view
		renderTabs()
		if wasShowingConversation
		{
			onTabSelectionChange?()
		}
	}

	func setConversationTitle(_ title: String)
	{
		guard conversationTitle != title
		else
		{
			return
		}
		conversationTitle = title
		if isExpanded
		{
			renderTabs()
		}
	}

	func setExpanded(_ expanded: Bool)
	{
		_ = view
		isExpanded = expanded
		if !expanded
		{
			isConversationSelected = false
		}
		summaryButton.isHidden = !expanded
		let label = expanded ? "Restore split view" : "Expand tab pane"
		expandButton?.image = DesktopIcons.image(
			expanded ? .collapseSmall : .expand,
			size: 16
		)
		expandButton?.toolTip = label
		expandButton?.setAccessibilityLabel(label)
		renderTabs()
	}

	func setSummaryVisible(_ visible: Bool)
	{
		summaryButton.state = visible ? .on : .off
		summaryButton.setAccessibilityValue(visible ? "Visible" : "Hidden")
	}

	private func configureSummaryButton()
	{
		DesktopTheme.styleButton(summaryButton)
		summaryButton.image = PinnedSummaryIcons.image(.toggle)
		summaryButton.imagePosition = .imageOnly
		summaryButton.setButtonType(.toggle)
		summaryButton.target = self
		summaryButton.action = #selector(toggleSummary)
		summaryButton.toolTip = "Toggle pinned summary"
		summaryButton.setAccessibilityLabel("Toggle pinned summary")
		summaryButton.widthAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		summaryButton.heightAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		summaryButton.isHidden = true
	}

	private func makeTabHeader() -> NSView
	{
		let header = NSView()
		configureTabScrollView()
		configureSummaryButton()
		let addButton = makeIconButton(
			.plus,
			label: "Add tab",
			action: #selector(addTab)
		)
		addTabButton = addButton
		let expandButton = makeIconButton(
			.expand,
			label: "Expand tab pane",
			action: #selector(toggleExpanded)
		)
		self.expandButton = expandButton
		let closePaneButton = makeIconButton(
			image: Self.paneIcon(),
			label: "Close tab pane",
			action: #selector(closePane)
		)

		let controls = AppKitLayout.horizontalStack(
			[summaryButton, expandButton, closePaneButton],
			spacing: Layout.controlSpacing
		)
		for child in [tabScrollView, controls]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(child)
		}
		let preferredWidth = tabScrollView.widthAnchor.constraint(equalToConstant: 0)
		preferredWidth.priority = .defaultHigh
		preferredTabAreaWidth = preferredWidth
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),
			preferredWidth,
			tabScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlSize),
			tabScrollView.leadingAnchor.constraint(
				equalTo: header.leadingAnchor,
				constant: 0
			),
			tabScrollView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			tabScrollView.heightAnchor.constraint(equalToConstant: Layout.tabHeight),
			tabScrollView.trailingAnchor.constraint(
				lessThanOrEqualTo: controls.leadingAnchor,
				constant: -Layout.addButtonSpacing
			),
			controls.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			controls.trailingAnchor.constraint(
				equalTo: header.trailingAnchor,
				constant: 0
			),
		])
		return header
	}

	private func configureTabScrollView()
	{
		tabStack.orientation = .horizontal
		tabStack.alignment = .centerY
		tabStack.spacing = Layout.tabSpacing
		tabStack.translatesAutoresizingMaskIntoConstraints = false

		tabScrollView.drawsBackground = false
		tabScrollView.hasHorizontalScroller = true
		tabScrollView.autohidesScrollers = true
		tabScrollView.scrollerStyle = .overlay
		tabScrollView.documentView = tabStack
		tabStack.heightAnchor.constraint(equalTo: tabScrollView.contentView.heightAnchor)
			.isActive = true
		tabScrollView.setAccessibilityLabel("Tools tabs")
	}

	private func makeToolsContent() -> NSStackView
	{
		let heading = NSTextField(labelWithString: "Tools")
		heading.font = .systemFont(
			ofSize: 13,
			weight: .medium
		)
		heading.textColor = .labelColor
		let tile = makeChangesTile()
		let content = AppKitLayout.verticalStack(
			[heading, tile],
			spacing: 16
		)
		let preferredWidth = tile.widthAnchor.constraint(equalToConstant: Layout.toolTileWidth)
		preferredWidth.priority = .defaultHigh
		NSLayoutConstraint.activate([
			tile.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.toolTileWidth),
			tile.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
			preferredWidth,
		])
		return content
	}

	private func makeChangesTile() -> NSView
	{
		let tile = DesktopSurface(
			DesktopTheme.sidebar,
			cornerRadius: 8
		)
		let button = NSButton(
			title: "Changes",
			target: nil,
			action: nil
		)
		DesktopTheme.styleButton(button)
		button.font = .systemFont(ofSize: 14)
		button.alignment = .left
		button.image = PinnedSummaryIcons.image(
			.changes,
			size: 18
		)
		button.imagePosition = .imageLeading
		button.isEnabled = false
		button.setAccessibilityLabel("Changes")
		AppKitLayout.pin(
			button,
			to: tile,
			inset: 12
		)
		tile.heightAnchor.constraint(equalToConstant: 42).isActive = true
		return tile
	}

	private func renderTabs()
	{
		let visibleTabCount = tabCount + (isExpanded ? 1 : 0)
		preferredTabAreaWidth?.constant = CGFloat(visibleTabCount) * Layout.tabWidth
			+ CGFloat(max(
				0,
				visibleTabCount - 1
			)) * Layout.tabSpacing + Layout.tabSpacing + Layout.controlSize
		for tab in tabStack.arrangedSubviews
		{
			tabStack.removeArrangedSubview(tab)
			tab.removeFromSuperview()
		}
		var selectedTab: NSView?
		if isExpanded
		{
			let tab = makeConversationTab()
			addTabView(tab)
			if isConversationSelected
			{
				selectedTab = tab
			}
		}
		for (index, tabID) in tabIDs.enumerated()
		{
			let selected = !isConversationSelected && tabID == selectedTabID
			let tab = makeTab(
				at: index,
				selected: selected
			)
			addTabView(tab)
			if selected
			{
				selectedTab = tab
			}
		}
		if let addTabButton
		{
			tabStack.addArrangedSubview(addTabButton)
		}
		if tabBar.superview != nil, tabBar.bounds.width > 0
		{
			tabBar.layoutSubtreeIfNeeded()
			if let selectedTab
			{
				var visibleRect = selectedTab.frame
				if !isConversationSelected, selectedTabID == tabIDs.last, let addTabButton
				{
					visibleRect = visibleRect.union(addTabButton.frame)
				}
				tabStack.scrollToVisible(visibleRect)
			}
		}
	}

	private func addTabView(_ tab: NSView)
	{
		tabStack.addArrangedSubview(tab)
		tab.widthAnchor.constraint(lessThanOrEqualTo: tabScrollView.contentView.widthAnchor)
			.isActive = true
	}

	private func makeConversationTab() -> NSView
	{
		let selectButton = NSButton(
			title: conversationTitle,
			target: self,
			action: #selector(selectConversation)
		)
		DesktopTheme.styleButton(
			selectButton,
			prominent: isConversationSelected
		)
		selectButton.image = DesktopIcons.image(.chat)
		selectButton.imagePosition = .imageLeading
		selectButton.alignment = .left
		selectButton.font = .systemFont(ofSize: 13)
		selectButton.cell?.lineBreakMode = .byTruncatingTail
		selectButton.toolTip = conversationTitle
		selectButton.setAccessibilityLabel("Chat: " + conversationTitle)
		selectButton.setAccessibilityValue(isConversationSelected ? "Selected" : "Not selected")
		let moreButton = makeIconButton(
			.dotsHorizontal,
			label: "Chat options",
			action: nil
		)
		moreButton.isEnabled = false
		return makeTabSurface(
			selectButton,
			trailingButton: moreButton,
			selected: isConversationSelected
		)
	}

	private func makeTab(
		at index: Int,
		selected: Bool
	) -> NSView
	{
		let selectButton = NSButton(
			title: "New tab",
			target: self,
			action: #selector(selectTab(_:))
		)
		DesktopTheme.styleButton(
			selectButton,
			prominent: selected
		)
		selectButton.alignment = .left
		selectButton.font = .systemFont(ofSize: 13)
		selectButton.tag = index
		selectButton.setAccessibilityLabel("New tab \(index + 1)")
		selectButton.setAccessibilityValue(selected ? "Selected" : "Not selected")
		let closeButton = makeIconButton(
			.x,
			label: "Close tab \(index + 1)",
			action: #selector(closeTab(_:))
		)
		closeButton.tag = index
		return makeTabSurface(
			selectButton,
			trailingButton: closeButton,
			selected: selected
		)
	}

	private func makeTabSurface(
		_ selectButton: NSButton,
		trailingButton: NSButton,
		selected: Bool
	) -> NSView
	{
		let tab = ToolsTabSurface(isSelected: selected)
		for child in [selectButton, trailingButton]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			tab.addSubview(child)
		}

		let preferredWidth = tab.widthAnchor.constraint(equalToConstant: Layout.tabWidth)
		// Keep titles from changing tab widths; the viewport cap can still shrink narrow tabs.
		preferredWidth.priority = NSLayoutConstraint.Priority(999)
		NSLayoutConstraint.activate([
			preferredWidth,
			tab.heightAnchor.constraint(equalToConstant: Layout.tabHeight),
			selectButton.leadingAnchor.constraint(
				equalTo: tab.leadingAnchor,
				constant: 12
			),
			selectButton.topAnchor.constraint(equalTo: tab.topAnchor),
			selectButton.bottomAnchor.constraint(equalTo: tab.bottomAnchor),
			selectButton.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor),
			trailingButton.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
			trailingButton.trailingAnchor.constraint(
				equalTo: tab.trailingAnchor,
				constant: -4
			),
		])
		return tab
	}

	private func makeIconButton(
		_ icon: DesktopIcon,
		label: String,
		action: Selector?
	) -> NSButton
	{
		makeIconButton(
			image: DesktopIcons.image(
				icon,
				size: 16
			),
			label: label,
			action: action
		)
	}

	private func makeIconButton(
		image: NSImage,
		label: String,
		action: Selector?
	) -> NSButton
	{
		let button = NSButton(
			title: "",
			target: self,
			action: action
		)
		DesktopTheme.styleButton(button)
		button.image = image
		button.imagePosition = .imageOnly
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.widthAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		button.heightAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		return button
	}

	@objc private func addTab()
	{
		openNewTab()
	}

	@objc private func closePane()
	{
		onClosePane?()
	}

	@objc private func toggleSummary()
	{
		onToggleSummary?()
	}

	@objc private func toggleExpanded()
	{
		onToggleExpanded?()
	}

	@objc private func selectTab(_ sender: NSButton)
	{
		guard tabIDs.indices.contains(sender.tag)
		else
		{
			return
		}
		selectedTabID = tabIDs[sender.tag]
		isConversationSelected = false
		renderTabs()
		onTabSelectionChange?()
	}

	@objc private func selectConversation()
	{
		guard isExpanded
		else
		{
			return
		}
		isConversationSelected = true
		renderTabs()
		onTabSelectionChange?()
	}

	@objc private func closeTab(_ sender: NSButton)
	{
		guard tabIDs.indices.contains(sender.tag)
		else
		{
			return
		}
		let removedTabID = tabIDs.remove(at: sender.tag)
		tabCount = tabIDs.count
		if removedTabID == selectedTabID
		{
			selectedTabID = tabIDs.isEmpty ? nil : tabIDs[min(
				sender.tag,
				tabIDs.count - 1
			)]
		}
		renderTabs()
		if tabIDs.isEmpty
		{
			onCloseLastTab?()
		}
		else
		{
			onTabSelectionChange?()
		}
	}
}
