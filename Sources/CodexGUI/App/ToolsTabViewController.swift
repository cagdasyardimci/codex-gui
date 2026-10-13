import AppKit

@MainActor
final class ToolsTabViewController: NSViewController
{
	private typealias Layout = LayoutTokens.Tabs

	var onCloseLastTab: (() -> Void)?
	var onClosePane: (() -> Void)?
	var onToggleExpanded: (() -> Void)?
	var onToggleSummary: (() -> Void)?
	var onTabSelectionChange: (() -> Void)?
	var onOpenChanges: (() -> Void)?
	var onChangesSelectionChange: (() -> Void)?
	var onChangesTabClosed: (() -> Void)?
	var onSourcesTabClosed: (() -> Void)?
	var onSubagentsTabClosed: (() -> Void)?
	private(set) var tabCount = 0
	private(set) var selectedTabID: UUID?
	private(set) var isConversationSelected = false
	private(set) var changesTabID: UUID?
	private(set) var sourcesTabID: UUID?
	private(set) var subagentsTabID: UUID?
	var isChangesSelected: Bool
	{
		!isConversationSelected && selectedTabID == changesTabID && changesTabID != nil
	}
	var isSourcesSelected: Bool
	{
		!isConversationSelected && selectedTabID == sourcesTabID && sourcesTabID != nil
	}
	var isSubagentsSelected: Bool
	{
		!isConversationSelected && selectedTabID == subagentsTabID && subagentsTabID != nil
	}
	private var isExpanded = false
	private var isContentVisible = true
	private var conversationTitle = "New chat"
	private var tabIDs: [UUID] = []
	private let tabStack = NSStackView()
	private let contentHost = NSView()
	private var toolsContent: NSView?
	private weak var changesController: NSViewController?
	private weak var sourcesController: NSViewController?
	private weak var subagentsController: NSViewController?
	private let sourcesHoverPreview = SourcesTabHoverPreview()
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
		let minimumTabWidth = Layout.tabLeadingInset + Layout.minimumTabSelectionWidth
			+ Layout.controlSize + Layout.tabTrailingInset
		return minimumTabWidth + Layout.controlSize * CGFloat(trailingControlCount)
			+ Layout.controlSpacing * CGFloat(trailingControlCount - 1)
			+ Layout.addButtonSpacing
	}

	static func paneIcon() -> NSImage
	{
		let configuration = NSImage.SymbolConfiguration(
			pointSize: 11,
			weight: .regular
		)
		let image = NSImage(
			systemSymbolName: "rectangle.split.2x1",
			accessibilityDescription: nil
		)?.withSymbolConfiguration(configuration) ?? DesktopIcons.image(
			.sidebarRight,
			size: 12
		)
		image.isTemplate = true
		return image
	}

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.canvas)
		view = container

		_ = tabBar
		AppKitLayout.pin(
			contentHost,
			to: container,
			inset: 0
		)
		installToolsContent()
		renderTabs()
	}

	private func installToolsContent()
	{
		let toolsContent = makeToolsContent()
		self.toolsContent = toolsContent
		toolsContent.translatesAutoresizingMaskIntoConstraints = false
		contentHost.addSubview(toolsContent)
		NSLayoutConstraint.activate([
			toolsContent.leadingAnchor.constraint(
				equalTo: contentHost.leadingAnchor,
				constant: Layout.contentInset
			),
			toolsContent.trailingAnchor.constraint(
				equalTo: contentHost.trailingAnchor,
				constant: -Layout.contentInset
			),
			toolsContent.topAnchor.constraint(
				equalTo: contentHost.topAnchor,
				constant: 32
			),
		])
	}

	func showChanges(_ controller: NSViewController)
	{
		guard selectedTabID != nil
		else
		{
			return
		}
		let selectionChanged = !isChangesSelected
		changesTabID = selectFeatureTab(changesTabID)
		_ = view
		installController(
			controller,
			replacing: changesController
		)
		changesController = controller
		renderTabs()
		if selectionChanged
		{
			onTabSelectionChange?()
		}
	}

	func detachChanges()
	{
		guard let changesController, changesController.parent === self
		else
		{
			return
		}
		changesController.view.removeFromSuperview()
		changesController.removeFromParent()
		showSelectedContent()
	}

	func showSources(_ controller: NSViewController)
	{
		sourcesTabID = selectFeatureTab(sourcesTabID)
		_ = view
		installController(
			controller,
			replacing: sourcesController
		)
		sourcesController = controller
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	func detachSources()
	{
		sourcesHoverPreview.dismiss()
		detachController(sourcesController)
		showSelectedContent()
	}

	func removeSourcesTab()
	{
		removeFeatureTab(sourcesTabID)
	}

	func showSubagents(_ controller: NSViewController)
	{
		subagentsTabID = selectFeatureTab(subagentsTabID)
		_ = view
		installController(
			controller,
			replacing: subagentsController
		)
		subagentsController = controller
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	func detachSubagents()
	{
		detachController(subagentsController)
		showSelectedContent()
	}

	func removeSubagentsTab()
	{
		removeFeatureTab(subagentsTabID)
	}

	private func selectFeatureTab(_ existingTabID: UUID?) -> UUID
	{
		let occupiedTabIDs = [changesTabID, sourcesTabID, subagentsTabID].compactMap
		{
			$0
		}
		let tabID: UUID
		if let existingTabID
		{
			tabID = existingTabID
		}
		else if !isConversationSelected, let selectedTabID,
				!occupiedTabIDs.contains(selectedTabID)
		{
			tabID = selectedTabID
		}
		else
		{
			tabID = UUID()
			tabIDs.append(tabID)
			tabCount = tabIDs.count
		}
		selectedTabID = tabID
		isConversationSelected = false
		return tabID
	}

	private func installController(
		_ controller: NSViewController,
		replacing previousController: NSViewController?
	)
	{
		if previousController !== controller
		{
			detachController(previousController)
		}
		guard controller.parent !== self
		else
		{
			return
		}
		controller.view.removeFromSuperview()
		controller.removeFromParent()
		addChild(controller)
		AppKitLayout.pin(
			controller.view,
			to: contentHost,
			inset: 0
		)
	}

	private func detachController(_ controller: NSViewController?)
	{
		guard let controller, controller.parent === self
		else
		{
			return
		}
		(controller as? SubagentsViewController)?.setPresentationVisible(false)
		controller.view.removeFromSuperview()
		controller.removeFromParent()
	}

	private func removeFeatureTab(_ tabID: UUID?)
	{
		guard let tabID, let index = tabIDs.firstIndex(of: tabID)
		else
		{
			return
		}
		removeTab(at: index)
	}

	func openNewTab()
	{
		let wasShowingConversation = isConversationSelected
		let wasShowingFeature = isSourcesSelected || isSubagentsSelected
		isConversationSelected = false
		let tabID = UUID()
		tabIDs.append(tabID)
		tabCount = tabIDs.count
		selectedTabID = tabID

		_ = view
		renderTabs()
		onChangesSelectionChange?()
		if wasShowingConversation || wasShowingFeature
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
		if !expanded && isChangesSelected
		{
			onChangesSelectionChange?()
		}
	}

	func setSummaryVisible(_ visible: Bool)
	{
		summaryButton.state = visible ? .on : .off
		summaryButton.setAccessibilityValue(visible ? "Visible" : "Hidden")
	}

	func setContentVisible(_ visible: Bool)
	{
		isContentVisible = visible
		showSelectedContent()
	}

	private func configureSummaryButton()
	{
		AppKitControlStyling.styleButton(summaryButton)
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
			AppKitColorTokens.sidebar,
			cornerRadius: 8
		)
		let button = NSButton(
			title: "Changes",
			target: nil,
			action: nil
		)
		AppKitControlStyling.styleButton(button)
		button.font = .systemFont(ofSize: 14)
		button.alignment = .left
		button.image = PinnedSummaryIcons.image(
			.changes,
			size: 18
		)
		button.imagePosition = .imageLeading
		button.target = self
		button.action = #selector(openChanges)
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
		showSelectedContent()
		updatePreferredTabAreaWidth()

		let selectedTab = rebuildTabViews()
		revealSelectedTab(selectedTab)
	}

	private func updatePreferredTabAreaWidth()
	{
		let visibleTabCount = tabCount + (isExpanded ? 1 : 0)
		let tabsWidth = CGFloat(visibleTabCount) * Layout.tabWidth
		let tabGapCount = max(
			0,
			visibleTabCount - 1
		)
		let tabGapsWidth = CGFloat(tabGapCount) * Layout.tabSpacing
		let tabsAndGapsWidth = tabsWidth + tabGapsWidth
		preferredTabAreaWidth?.constant =
			tabsAndGapsWidth + Layout.tabSpacing + Layout.controlSize
	}

	private func rebuildTabViews() -> NSView?
	{
		sourcesHoverPreview.dismiss()
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
				id: tabID,
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
		return selectedTab
	}

	private func revealSelectedTab(_ selectedTab: NSView?)
	{
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

	private func showSelectedContent()
	{
		toolsContent?.isHidden = isChangesSelected || isSourcesSelected ||
			isSubagentsSelected || isConversationSelected
		if let changesController, changesController.parent === self
		{
			changesController.view.isHidden = !isChangesSelected
		}
		if let subagentsController, subagentsController.parent === self
		{
			subagentsController.view.isHidden = !isSubagentsSelected
			(subagentsController as? SubagentsViewController)?
				.setPresentationVisible(isContentVisible && isSubagentsSelected)
		}

		if let sourcesController, sourcesController.parent === self
		{
			sourcesController.view.isHidden = !isSourcesSelected
			if isSourcesSelected
			{
				(sourcesController as? ConversationSourcesViewController)?.prepareForDisplay()
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
		AppKitControlStyling.styleButton(
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
		id: UUID,
		selected: Bool
	) -> NSView
	{
		let isChanges = id == changesTabID
		let isSources = id == sourcesTabID
		let isSubagents = id == subagentsTabID
		let title = isChanges ? "Changes" :
			isSources ? "Sources" : isSubagents ? "Subagents" : "New tab"
		let selectButton = NSButton(
			title: title,
			target: self,
			action: #selector(selectTab(_:))
		)
		AppKitControlStyling.styleButton(
			selectButton,
			prominent: selected
		)
		selectButton.alignment = .left
		if isChanges
		{
			selectButton.image = PinnedSummaryIcons.image(
				.changes,
				size: 16
			)
			selectButton.imagePosition = .imageLeading
		}
		else if isSources
		{
			selectButton.image = DesktopIcons.image(
				.addSources,
				size: 16
			)
			selectButton.imagePosition = .imageLeading
		}
		else if isSubagents
		{
			selectButton.image = NSImage(
				systemSymbolName: "person.2",
				accessibilityDescription: "Subagents"
			)
			selectButton.imagePosition = .imageLeading
		}

		selectButton.font = .systemFont(ofSize: 13)
		selectButton.tag = index
		selectButton.setAccessibilityLabel("\(title) \(index + 1)")
		selectButton.setAccessibilityValue(selected ? "Selected" : "Not selected")
		let closeButton = makeIconButton(
			.x,
			label: "Close tab \(index + 1)",
			action: #selector(closeTab(_:))
		)
		closeButton.tag = index
		let tab = makeTabSurface(
			selectButton,
			trailingButton: closeButton,
			selected: selected
		)
		if isSources, let surface = tab as? ToolsTabSurface
		{
			surface.onHoverChange =
			{
				[weak self, weak surface] hovered in
				guard let self
				else
				{
					return
				}
				if hovered, let surface,
					let controller = self.sourcesController as? ConversationSourcesViewController,
					controller.parent === self
				{
					self.sourcesHoverPreview.show(
						sources: controller.sources,
						below: surface
					)
				}
				else
				{
					self.sourcesHoverPreview.dismiss()
				}
			}
		}
		return tab
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
				constant: Layout.tabLeadingInset
			),
			selectButton.topAnchor.constraint(equalTo: tab.topAnchor),
			selectButton.bottomAnchor.constraint(equalTo: tab.bottomAnchor),
			selectButton.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor),
			trailingButton.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
			trailingButton.trailingAnchor.constraint(
				equalTo: tab.trailingAnchor,
				constant: -Layout.tabTrailingInset
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
		AppKitControlStyling.styleButton(button)
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

	@objc private func openChanges()
	{
		onOpenChanges?()
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
		onChangesSelectionChange?()
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
		onChangesSelectionChange?()
	}

	@objc private func closeTab(_ sender: NSButton)
	{
		removeTab(at: sender.tag)
	}

	private func removeTab(at index: Int)
	{
		guard tabIDs.indices.contains(index)
		else
		{
			return
		}
		let removedTabID = tabIDs.remove(at: index)
		let removedSources = removedTabID == sourcesTabID
		if removedSources
		{
			sourcesTabID = nil
			detachSources()
		}
		let removedSubagents = removedTabID == subagentsTabID
		if removedSubagents
		{
			subagentsTabID = nil
			detachSubagents()
		}

		if removedTabID == changesTabID
		{
			changesTabID = nil
			onChangesTabClosed?()
		}
		tabCount = tabIDs.count
		if removedTabID == selectedTabID
		{
			selectedTabID = tabIDs.isEmpty ? nil : tabIDs[min(
				index,
				tabIDs.count - 1
			)]
		}
		renderTabs()
		if removedSources
		{
			onSourcesTabClosed?()
		}
		if removedSubagents
		{
			onSubagentsTabClosed?()
		}

		onChangesSelectionChange?()
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
