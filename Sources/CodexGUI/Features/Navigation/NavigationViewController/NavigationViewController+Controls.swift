import AppKit

extension NavigationViewController
{
	func makeBrandRow() -> NSStackView
	{
		let refreshButton = SidebarIconButton(
			role: .refresh,
			target: self,
			action: #selector(refresh)
		)

		let wordmark = NSImageView(image: DesktopBrandWordmark.image)
		wordmark.contentTintColor = AppKitColorTokens.primaryText
		wordmark.setAccessibilityLabel("Codex")
		wordmark.widthAnchor.constraint(equalToConstant: DesktopBrandWordmark.size.width)
			.isActive = true
		wordmark.heightAnchor.constraint(equalToConstant: DesktopBrandWordmark.size.height)
			.isActive = true

		searchButton.target = self
		searchButton.action = #selector(toggleSearch)
		searchButton.setAccessibilityLabel("Search conversation titles and previews")
		searchButton.toolTip = "Search conversation titles and previews"

		let brandRow = AppKitLayout.horizontalStack(
			[wordmark, NSView(), refreshButton, searchButton],
			spacing: 6
		)
		brandRow.edgeInsets = NSEdgeInsets(
			top: 0,
			left: 8,
			bottom: 0,
			right: 0
		)

		return brandRow
	}

	func configureNewChatButton()
	{
		newChatButton.target = self
		newChatButton.action = #selector(newChat)
	}

	func makeProjectsHeader(actionsButton: SidebarIconButton? = nil) -> NSStackView
	{
		let sidebarOptionsButton = actionsButton ?? self.sidebarOptionsButton
		let projectsCaption = SidebarTextField(
			labelWithString: sidebarPreferences.organization == .oneList ? "Recents" : "Projects"
		)
		projectsCaption.font = AppKitFontResolver.font(TypographyTokens.Sidebar.section)
		projectsCaption.textColor = AppKitColorTokens.secondaryText
		sidebarOptionsButton.target = self
		sidebarOptionsButton.action = #selector(showSidebarMenu(_:))
		sidebarOptionsButton.setAccessibilityLabel("Organize sidebar and sort chats")
		sidebarOptionsButton.toolTip = "Organize sidebar and sort chats"
		let addButton = actionsButton == nil ? projectActionsButton : SidebarIconButton(role: .add)
		addButton.target = self
		addButton.action = sidebarPreferences.organization == .oneList
			? #selector(newChat) : #selector(openProject)
		addButton.setAccessibilityLabel(
			sidebarPreferences.organization == .oneList ? "New chat" : "Add new project"
		)
		addButton.toolTip =
			sidebarPreferences.organization == .oneList ? "New chat" : "Add new project"
		let projectsHeader = makeSidebarHeading([
			projectsCaption,
			NSView(),
			sidebarOptionsButton,
			addButton
		])
		projectsHeader.hoverButtons = [sidebarOptionsButton, addButton]
		let management = NavigationContextMenu(title: "Project management")
		management.addAction(
			title: "Project and conversation actions",
			icon: .folder,
			callback:
			{
				[weak self, weak addButton] in
				self?.toggleProjectActions(addButton)
			}
		)
		projectsHeader.menu = management
		return projectsHeader
	}

	func makeSidebarHeading(_ views: [NSView]) -> SidebarHeadingView
	{
		let header = SidebarHeadingView(views: views)
		header.orientation = .horizontal
		header.alignment = .centerY
		header.spacing = LayoutTokens.LayoutDefaults.horizontalSpacing
		header.detachesHiddenViews = false
		header.edgeInsets = NSEdgeInsets(
			top: 0,
			left: NavigationSidebarLayout.cellInset,
			bottom: 0,
			right: 0
		)
		header.heightAnchor.constraint(equalToConstant: NavigationSidebarLayout.rowHeight)
			.isActive = true
		return header
	}

	func makeProjectSelectionRow() -> NSStackView
	{
		let openButton = DesktopStyledButton(
			title: "Open…",
			target: self,
			action: #selector(openProject)
		)
		openButton.setAccessibilityLabel("Open repository")
		openButton.symbol = .folderPlus
		openButton.size = .small

		recentProjectsButton.target = self
		recentProjectsButton.action = #selector(selectRecentProject)
		recentProjectsButton.setAccessibilityLabel("Recent projects")
		recentProjectsButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		recentProjectsButton.cell?.lineBreakMode = .byTruncatingTail

		recentProjectsButton.size = .small

		return AppKitLayout.horizontalStack(
			[openButton, recentProjectsButton, NSView()],
			spacing: 10
		)
	}

	func configureSearchPopover()
	{
		searchField.presentation = .viewerOverlay
		searchField.configureSearch(
			placeholder: "Search chats",
			accessibilityLabel: "Search conversation titles and previews",
			delegate: self,
			sendsImmediately: true
		)
		chatSearchController.onChoose =
		{
			[weak self] thread in
			self?.chooseSearchThread(thread)
		}
		chatSearchController.onNewChat =
		{
			[weak self] in
			self?.searchPopover.close()
			self?.onNewChat?()
		}
		chatSearchController.onCancel =
		{
			[weak self] in self?.searchPopover.close()
		}
		searchPopover.onKeyDown =
		{
			[weak self] event in self?.chatSearchController.handleKeyEquivalent(event) ?? false
		}
	}

	func configureThreadManagementControls()
	{
		renameButton.target = self
		renameButton.action = #selector(renameThread)
		renameButton.setAccessibilityLabel("Rename selected conversation")
		renameButton.symbol = .pencil
		renameButton.size = .small

		archiveButton.target = self
		archiveButton.action = #selector(archiveThread)
		archiveButton.setAccessibilityLabel("Archive or restore selected conversation")
		archiveButton.symbol = .archive
		archiveButton.size = .small

	}

	func makeConversationScrollView() -> NSScrollView
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conversations"))
		column.title = "Conversations"
		chatsTable.addTableColumn(column)
		chatsTable.style = .plain
		chatsTable.headerView = nil
		chatsTable.rowHeight = NavigationSidebarLayout.rowHeight
		chatsTable.intercellSpacing = NSSize(
			width: 0,
			height: NavigationSidebarLayout.rowSpacing
		)
		chatsTable.backgroundColor = .clear
		chatsTable.usesAlternatingRowBackgroundColors = false
		chatsTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		chatsTable.target = self
		chatsTable.action = #selector(sidebarClicked)
		chatsTable.delegate = self
		chatsTable.dataSource = self
		chatsTable.registerForDraggedTypes([Self.sidebarThreadPasteboardType])
		chatsTable.setDraggingSourceOperationMask(
			.move,
			forLocal: true
		)
		chatsTable.onContextMenuForRow =
		{
			[weak self] row in self?.taskContextMenu(for: row)
		}
		chatsTable.setAccessibilityLabel("Projects and saved conversations")

		let chatScrollView = NSScrollView()
		chatScrollView.documentView = chatsTable
		chatScrollView.hasVerticalScroller = true
		chatScrollView.autohidesScrollers = true
		chatScrollView.drawsBackground = false
		chatScrollView.borderType = .noBorder
		chatScrollView.automaticallyAdjustsContentInsets = false
		chatScrollView.contentInsets = NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)

		return chatScrollView
	}

	func configureProjectActionsPopover(
		projectButtons: NSStackView,
		taskRow: NSStackView,
		activeTaskRow: NSStackView
	)
	{
		let managementRow = AppKitLayout.horizontalStack(
			[renameButton, archiveButton, NSView()],
			spacing: 12
		)

		let actionsController = NSViewController()
		let actionsContainer = NSView()
		let actionsStack = AppKitLayout.verticalStack(
			[
				projectButtons,
				taskRow,
				activeTaskRow,
				managementRow
			],
			spacing: 10
		)
		AppKitLayout.pin(
			actionsStack,
			to: actionsContainer,
			inset: 12
		)
		for row in [projectButtons, taskRow, activeTaskRow, managementRow]
		{
			row.widthAnchor.constraint(equalTo: actionsStack.widthAnchor).isActive = true
		}
		taskPicker.widthAnchor.constraint(equalTo: actionsStack.widthAnchor).isActive = true
		actionsContainer.widthAnchor.constraint(equalToConstant: 280).isActive = true
		actionsController.view = actionsContainer
		projectActionsPopover.contentViewController = actionsController
		projectActionsPopover.behavior = .transient

		let infoController = NSViewController()
		infoController.view = projectInfoView
		projectInfoPopover.contentViewController = infoController
		projectInfoPopover.behavior = .transient
	}

}
