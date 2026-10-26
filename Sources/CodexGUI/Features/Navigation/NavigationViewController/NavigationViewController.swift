import AppKit

@MainActor
final class NavigationViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	NSSearchFieldDelegate
{
	var onLoadSidebarThreads: (() -> Void)?
	var onSelectSidebarTask: ((ThreadSummary) -> Void)?
	let sidebarMenu = SidebarOrganizationMenu()
	var sidebarLoadTask: Task<Void, Never>?
	var onOpenProject: (() -> Void)?
	var onSelectRecentProject: ((URL) -> Void)?
	var onNewChat: (() -> Void)?
	var onRefresh: (() -> Void)?
	var onSelectThread: ((String) -> Void)?
	var onSelectPinnedTask: ((ThreadSummary) -> Void)?
	var onRenameTask: ((String, String) -> Void)?
	var onToggleTaskPin: ((ThreadSummary) -> Void)?
	var onSelectWorkspace: ((UUID?) -> Void)?
	var onCreateTask: ((String) -> Void)?
	var onRemoveWorkspace: ((UUID) -> Void)?
	var onCancelWorkspaceCreation: ((UUID) -> Void)?
	var onReturnToActiveTask: (() -> Void)?
	var onSetArchivedFilter: ((Bool) -> Void)?
	var onRenameThread: ((String) -> Void)?
	var onArchiveThread: (() -> Void)?
	var onArchiveTask: ((String) -> Void)?
	var onDeleteTask: ((String) -> Void)?
	var onToggleProjectPin: ((URL) -> Void)?
	var onArchiveProjectChats: ((URL) -> Void)?
	var onRemoveProject: ((URL) -> Void)?
	var onRenameProject: ((URL, String) -> Void)?
	var onNewChatInProject: ((URL) -> Void)?

	var sidebarPreferences = SidebarPreferences()

	let recentProjectsButton = DesktopPopupButton()
	let taskPicker = DesktopPopupButton()
	let taskSummaryLabel = NSTextField(labelWithString: "")
	let activeTaskLabel = NSTextField(labelWithString: "")
	let returnToTaskButton = DesktopStyledButton(
		title: "Return to Task",
		target: nil,
		action: nil
	)
	let newChatButton = SidebarNewChatButton()
	let chatsTable = NavigationTasksTableView()
	let searchField = ViewerSearchField()
	let searchButton = SidebarIconButton(role: .search)
	lazy var chatSearchController = ChatSearchController(searchField: searchField)
	lazy var searchPopover = DesktopSearchPanel(
		controller: chatSearchController,
		placement: .centered,
		size: NSSize(
			width: 520,
			height: 480
		)
	)
	let sidebarOptionsButton = SidebarIconButton(role: .options)
	let projectActionsButton = SidebarIconButton(role: .add)
	let projectActionsPopover = NSPopover()
	let projectInfoPopover = NSPopover()
	let projectInfoView = ProjectInfoPopoverView(frame: .zero)
	let renameButton = DesktopStyledButton(
		title: "Rename…",
		target: nil,
		action: nil
	)
	let archiveButton = DesktopStyledButton(
		title: "Archive",
		target: nil,
		action: nil
	)
	let emptyLabel = DesktopStatusView(
		message: "",
		presentation: .inlineCompact
	)
	struct ModalScope: Equatable
	{
		let owner: WorkspaceLifecycleOwnerReference?
		let selectionEpoch: Int
		let conversation: ConversationKey
		let draftLifetime: Int
		let projectPath: String?
	}
	var modalScope: ModalScope?
	var threads: [ThreadSummary] = []
	var visibleThreads: [ThreadSummary] = []
	var recentProjects: [URL] = []
	var currentProject: URL?
	var isCurrentProjectCollapsed = false
	var projectTaskLimit = 5
	var pinnedProjectPaths: Set<String> = []
	var removedProjectPaths: Set<String> = []
	var pinnedTasks: [ThreadSummary] = []
	var projectsHeader: NSStackView?
	var manuallyUnreadThreadIDs: Set<String> = []
	var projectDisplayNames: [String: String] = [:]
	var projectInfoProject: URL?
	var currentProjectActiveTaskCount = 0
	var canStartProjectChat = false
	var sidebarItems: [NavigationSidebarItem] = []
	var updatingSidebarSelection = false
	var selectedThreadID: String?
	var selectedWorkspaceID: UUID?
	var activeThreadID: String?
	var activeExecutionState: ExecutionState?
	private var canManageSelectedThread = false
	var canManageSidebarTasks = false

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.sidebar)

		let brandRow = makeBrandRow()
		configureNewChatButton()
		let projectsHeader = makeProjectsHeader()
		self.projectsHeader = projectsHeader

		let chatScrollView = makeConversationScrollView()

		configureSearchPopover()
		configureThreadManagementControls()
		configureProjectActionsPopover(
			projectButtons: makeProjectSelectionRow(),
			taskRow: makeTaskSelectionRow(),
			activeTaskRow: makeActiveTaskRow()
		)

		let stack = AppKitLayout.verticalStack(
			[
				brandRow,
				newChatButton,
				projectsHeader,
				chatScrollView,
				emptyLabel,
			],
			spacing: 6
		)
		stack.setCustomSpacing(
			0,
			after: brandRow
		)
		stack.setCustomSpacing(
			12,
			after: newChatButton
		)
		stack.setCustomSpacing(
			NavigationSidebarLayout.sectionContentSpacing,
			after: projectsHeader
		)
		container.addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 8
			),
			stack.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -8
			),
			stack.topAnchor.constraint(equalTo: container.topAnchor),
			stack.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -8
			),
		])
		for row in [brandRow, projectsHeader]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		newChatButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		brandRow.heightAnchor.constraint(equalToConstant: 52).isActive = true
		chatScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		chatScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
		chatScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)

		view = container
		filterThreads()
	}

	/// Read-only menu inspection also works while the transient project-actions popover is closed.
	var taskMenuItems: [NSMenuItem]
	{
		taskPicker.itemArray
	}

	var unreadThreadIDs: Set<String> = []
	private var unreadTracker = TaskUnreadTracker()
	private(set) var renderedPresentation: NavigationPresentation?
	private var renderedManagementAvailability = false

	func render(_ snapshot: ConversationSnapshot)
	{
		render(NavigationPresentation(snapshot))
	}

	func render(_ snapshot: NavigationPresentation)
	{
		_ = view
		modalScope = ModalScope(
			owner: snapshot.owner.runtimeOwner,
			selectionEpoch: snapshot.owner.selectionEpoch,
			conversation: snapshot.selectedThreadID
				.map(ConversationKey.thread) ?? .newChat,
			draftLifetime: snapshot.draftLifetime,
			projectPath: snapshot.projectPath
		)
		let previousPresentation = renderedPresentation
		if previousPresentation?.owner.projectIdentity != snapshot.owner.projectIdentity
		{
			sidebarMenu.close()
		}
		let sidebarRefreshNeeded = snapshot.sidebarConnectionGeneration != nil && (
			previousPresentation?.owner.projectIdentity != snapshot.owner.projectIdentity
				|| previousPresentation?.sidebarConnectionGeneration != snapshot
				.sidebarConnectionGeneration
				|| previousPresentation?.threads != snapshot.threads
				|| previousPresentation?.showingArchived != snapshot.showingArchived
		)
		if sidebarPreferences.organization == .oneList && sidebarRefreshNeeded
		{
			sidebarLoadTask?.cancel()
			let callback = onLoadSidebarThreads
			sidebarLoadTask = Task
			{
				@MainActor in
				guard !Task.isCancelled
				else
				{
					return
				}
				callback?()
			}
		}
		guard previousPresentation != snapshot
		else
		{
			return
		}
		if selectedThreadID != snapshot.selectedThreadID, let selected = snapshot.selectedThreadID
		{
			manuallyUnreadThreadIDs.remove(selected)
		}
		let nextUnreadThreadIDs = unreadTracker.observe(snapshot).union(manuallyUnreadThreadIDs)
		let unreadChanged = unreadThreadIDs != nextUnreadThreadIDs
		unreadThreadIDs = nextUnreadThreadIDs
		renderedPresentation = snapshot
		let nextProject = snapshot.projectPath.map
		{
			URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath()
		}
		let projectsChanged =
			currentProject != nextProject || recentProjects != snapshot.recentProjects
				|| pinnedProjectPaths != snapshot.pinnedProjectPaths
				|| removedProjectPaths != snapshot.removedProjectPaths
				|| pinnedTasks != snapshot.pinnedTasks
				|| projectDisplayNames != snapshot.projectDisplayNames
		if currentProject != nextProject
		{
			isCurrentProjectCollapsed = false
			projectTaskLimit = 5
		}
		currentProject = nextProject
		recentProjects = snapshot.recentProjects
		pinnedProjectPaths = snapshot.pinnedProjectPaths
		removedProjectPaths = snapshot.removedProjectPaths
		pinnedTasks = snapshot.pinnedTasks
		projectDisplayNames = snapshot.projectDisplayNames
		let previousCanStartProjectChat = canStartProjectChat

		let menuOwnerChanged =
			previousPresentation?.owner.projectIdentity != snapshot.owner.projectIdentity
		let canCreateTask = !snapshot.recentProjects.isEmpty || snapshot.projectPath != nil
		let couldCreateTask = previousPresentation.map
		{
			!$0.recentProjects.isEmpty || $0.projectPath != nil
		}
		let workspaceMenuMatches = previousPresentation.map
		{
			NavigationMenuContent.sameWorkspaces(
				$0.taskWorkspaces,
				snapshot.taskWorkspaces
			)
		} ?? false
		let taskMenuChanged =
			menuOwnerChanged || !workspaceMenuMatches || couldCreateTask != canCreateTask
		renderTaskWorkspaces(
			snapshot,
			rebuildMenu: taskMenuChanged
		)

		let activeThreadChanged = activeThreadID != snapshot.activeThreadID
		let activeStateChanged = activeExecutionState != snapshot.activeExecutionState
		activeThreadID = snapshot.activeThreadID
		activeExecutionState = snapshot.activeExecutionState

		_ = renderTaskStatus(snapshot)
		renderThreadAvailability(snapshot)

		let shouldReloadSidebar =
			threads != snapshot.threads || previousPresentation?.sidebarThreads != snapshot
				.sidebarThreads
				|| previousPresentation?.sidebarListLoading != snapshot.sidebarListLoading
				|| previousPresentation?.sidebarListError != snapshot.sidebarListError
				|| selectedThreadID != snapshot.selectedThreadID
				|| activeThreadChanged || activeStateChanged || projectsChanged || unreadChanged
				|| previousPresentation?.threadExecutions != snapshot.threadExecutions
				|| previousPresentation?.threadManagementAvailability
				!= snapshot.threadManagementAvailability
				|| previousCanStartProjectChat != canStartProjectChat
				|| renderedManagementAvailability != snapshot.canManageThreads

		renderedManagementAvailability = snapshot.canManageThreads
		if shouldReloadSidebar
		{
			threads = snapshot.threads
			selectedThreadID = snapshot.selectedThreadID
			filterThreads()
		}
		updateManagementButtons()

		let projectNamesMatch = previousPresentation.map
		{
			NavigationMenuContent.sameProjectNames(
				$0.projectDisplayNames,
				snapshot.projectDisplayNames
			)
		} ?? false
		if menuOwnerChanged || previousPresentation?.recentProjects != snapshot.recentProjects
			|| !projectNamesMatch
		{
			renderRecentProjects(snapshot.recentProjects)
		}
		if projectActionsPopover.isShown
		{
			resizeProjectActionsPopover()
		}
		if projectInfoPopover.isShown
		{
			refreshProjectInfo()
		}
	}

	private func renderThreadAvailability(_ snapshot: NavigationPresentation)
	{
		let waitingForThreadID = snapshot.executionState.isBusy && snapshot.activeThreadID == nil
		newChatButton.isEnabled = snapshot.selectedTaskWorkspaceID == nil
		currentProjectActiveTaskCount = snapshot.activeExecutionCount
			?? snapshot.threadExecutions.values.filter
			{
				$0.state.isBusy
			}.count + (waitingForThreadID ? 1 : 0)
		canStartProjectChat = newChatButton.isEnabled
		chatsTable.isEnabled = true
		canManageSidebarTasks = snapshot.canManageThreads
		canManageSelectedThread = snapshot.selectedThreadID.map(canManageTask) ?? false
		archiveButton.title = snapshot.showingArchived ? "Restore" : "Archive"
		archiveButton.toolTip = archiveButton.title
	}

	func canManageTask(_ threadID: String) -> Bool
	{
		if let availability = renderedPresentation?.threadManagementAvailability
		{
			return availability[threadID] ?? false
		}
		return canManageSidebarTasks
	}

	func updateManagementButtons()
	{
		let canManageVisibleSelection = canManageSelectedThread && visibleThreads
			.contains
			{
				$0.id == selectedThreadID
			}
		renameButton.isEnabled = canManageVisibleSelection
		archiveButton.isEnabled = canManageVisibleSelection
		renameButton.superview?.isHidden = !canManageVisibleSelection
		if let thread = visibleThreads.first(where:
			{
				$0.id == selectedThreadID
			})
		{
			let title = thread.displayTitle
			renameButton.setAccessibilityLabel("Rename conversation \(title)")
			archiveButton.setAccessibilityLabel("\(archiveButton.title) conversation \(title)")
			renameButton.toolTip = "Rename \(title)"
			archiveButton.toolTip = "\(archiveButton.title) \(title)"
		}
	}

	@objc func archiveThread()
	{
		guard archiveButton.isEnabled,
				visibleThreads.contains(where:
				{
					$0.id == selectedThreadID
				})
		else
		{
			return
		}
		projectActionsPopover.performClose(nil)
		onArchiveThread?()
	}

	@objc func newChat()
	{
		onNewChat?()
	}
	@objc func refresh()
	{
		if sidebarPreferences.organization == .oneList
		{
			onLoadSidebarThreads?()
		}
		onRefresh?()
	}

}
