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

		let brandLabel = NSTextField(labelWithString: "Codex")
		brandLabel.font = .systemFont(
			ofSize: 18,
			weight: .semibold
		)

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
			[brandLabel, NSView(), refreshButton, searchButton],
			spacing: 6
		)
		refreshButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
		searchButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
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
		let projectsHeader = AppKitLayout.horizontalStack(
			[projectsCaption, NSView(), projectActionsButton]
		)
		projectActionsButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		projectActionsButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
		return projectsHeader
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
		searchField.placeholderString = "Search titles and previews"
		searchField.controlSize = .small
		searchField.font = .systemFont(ofSize: 12)
		searchField.setAccessibilityLabel("Search conversation titles and previews")
		searchField.delegate = self
		searchField.sendsSearchStringImmediately = true

		let searchController = NSViewController()
		let searchContainer = NSView()
		AppKitLayout.pin(
			searchField,
			to: searchContainer,
			inset: 12
		)
		searchController.view = searchContainer
		searchPopover.contentViewController = searchController
		searchPopover.contentSize = NSSize(
			width: 280,
			height: 50
		)
		searchPopover.behavior = .transient
		searchField.heightAnchor.constraint(equalToConstant: 26).isActive = true
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
		chatsTable.rowHeight = 30
		chatsTable.intercellSpacing = NSSize(
			width: 0,
			height: 2
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
