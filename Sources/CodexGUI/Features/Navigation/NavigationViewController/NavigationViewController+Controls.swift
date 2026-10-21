import AppKit

extension NavigationViewController
{
	func makeBrandRow() -> NSStackView
	{
		let refreshButton = NSButton(
			title: "Refresh",
			target: self,
			action: #selector(refresh)
		)
		refreshButton.setAccessibilityLabel("Refresh conversations")
		AppKitControlStyling.styleButton(
			refreshButton,
			icon: .arrowRotateCw
		)
		refreshButton.imagePosition = .imageOnly
		refreshButton.toolTip = "Refresh conversations"

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
		AppKitControlStyling.styleButton(
			searchButton,
			icon: .search
		)
		searchButton.imagePosition = .imageOnly
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
		refreshButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
		searchButton.image = DesktopIcons.image(
			.search,
			size: 16
		)
		searchButton.contentTintColor = AppKitColorTokens.secondaryText
		searchButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
		searchButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
		return brandRow
	}

	func configureNewChatButton()
	{
		newChatButton.cell = NewChatButtonCell(textCell: newChatButton.title)
		newChatButton.target = self
		newChatButton.action = #selector(newChat)
		newChatButton.setAccessibilityLabel("Start a new conversation")
		AppKitControlStyling.styleButton(
			newChatButton,
			icon: .chatCompose
		)
		newChatButton.font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		newChatButton.contentTintColor = AppKitColorTokens.sidebarText
		newChatButton.image = DesktopIcons.image(.chatCompose)
		newChatButton.alignment = .left
	}

	func makeProjectsHeader(actionsButton: NSButton? = nil) -> NSStackView
	{
		let projectActionsButton = actionsButton ?? self.projectActionsButton
		let projectsCaption = SidebarTextField(labelWithString: "Projects")
		projectsCaption.font = AppKitFontResolver.font(TypographyTokens.Sidebar.section)
		projectsCaption.textColor = AppKitColorTokens.secondaryText
		projectActionsButton.target = self
		projectActionsButton.action = #selector(toggleProjectActions(_:))
		projectActionsButton.setAccessibilityLabel("Project and conversation actions")
		AppKitControlStyling.styleButton(
			projectActionsButton,
			icon: .dotsHorizontal
		)
		projectActionsButton.imagePosition = .imageOnly
		projectActionsButton.toolTip = "Project and conversation actions"
		let projectsHeader = makeSidebarHeading([projectsCaption, NSView(), projectActionsButton])
		projectActionsButton.widthAnchor
			.constraint(equalToConstant: LayoutTokens.Sidebar.headingActionSize).isActive = true
		projectActionsButton.heightAnchor
			.constraint(equalToConstant: LayoutTokens.Sidebar.headingActionSize).isActive = true
		return projectsHeader
	}

	func makeSidebarHeading(_ views: [NSView]) -> NSStackView
	{
		let header = AppKitLayout.horizontalStack(views)
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
		let openButton = NSButton(
			title: "Open…",
			target: self,
			action: #selector(openProject)
		)
		openButton.setAccessibilityLabel("Open repository")
		AppKitControlStyling.styleButton(
			openButton,
			icon: .folderPlus
		)
		openButton.font = .systemFont(ofSize: 11)

		recentProjectsButton.target = self
		recentProjectsButton.action = #selector(selectRecentProject)
		recentProjectsButton.setAccessibilityLabel("Recent projects")
		recentProjectsButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		recentProjectsButton.cell?.lineBreakMode = .byTruncatingTail
		AppKitControlStyling.stylePopup(recentProjectsButton)
		recentProjectsButton.font = .systemFont(ofSize: 11)

		return AppKitLayout.horizontalStack(
			[openButton, recentProjectsButton, NSView()],
			spacing: 10
		)
	}

	func configureSearchPopover()
	{
		searchField.placeholderString = "Search chats"
		searchField.font = .systemFont(ofSize: 14)
		searchField.drawsSurface = false
		(searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
		searchField.isBordered = false
		searchField.drawsBackground = false
		searchField.focusRingType = .none
		searchField.textColor = AppKitColorTokens.primaryText
		searchField.setAccessibilityLabel("Search conversation titles and previews")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true
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
		AppKitControlStyling.styleButton(
			renameButton,
			icon: .pencil
		)
		renameButton.font = .systemFont(ofSize: 11)

		archiveButton.target = self
		archiveButton.action = #selector(archiveThread)
		archiveButton.setAccessibilityLabel("Archive or restore selected conversation")
		AppKitControlStyling.styleButton(
			archiveButton,
			icon: .archive
		)
		archiveButton.font = .systemFont(ofSize: 11)

		emptyLabel.textColor = .secondaryLabelColor
		emptyLabel.font = .systemFont(ofSize: 11)
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
				taskSummaryLabel,
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
		for row in [projectButtons, taskRow, taskSummaryLabel, activeTaskRow, managementRow]
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
