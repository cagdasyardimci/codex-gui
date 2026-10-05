import AppKit

@MainActor
final class NavigationViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	NSSearchFieldDelegate
{
	var onOpenProject: (() -> Void)?
	var onSelectRecentProject: ((URL) -> Void)?
	var onNewChat: (() -> Void)?
	var onRefresh: (() -> Void)?
	var onSelectThread: ((String) -> Void)?
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
	var onRenameProject: ((URL, String) -> Void)?
	var onNewChatInProject: ((URL) -> Void)?

	let recentProjectsButton = NSPopUpButton()
	let taskPicker = NSPopUpButton()
	let taskSummaryLabel = NSTextField(labelWithString: "")
	let activeTaskLabel = NSTextField(labelWithString: "")
	let returnToTaskButton = NSButton(
		title: "Return to Task",
		target: nil,
		action: nil
	)
	let newChatButton = NSButton(
		title: "New Chat",
		target: nil,
		action: nil
	)
	let chatsTable = NSTableView()
	let searchField = NSSearchField()
	let searchButton = NSButton(
		title: "Search",
		target: nil,
		action: nil
	)
	let searchPopover = NSPopover()
	let projectActionsButton = NSButton(
		title: "Project Actions",
		target: nil,
		action: nil
	)
	let projectActionsPopover = NSPopover()
	let projectInfoPopover = NSPopover()
	let projectInfoView = ProjectInfoPopoverView(frame: .zero)
	let renameButton = NSButton(
		title: "Rename…",
		target: nil,
		action: nil
	)
	let archiveButton = NSButton(
		title: "Archive",
		target: nil,
		action: nil
	)
	let emptyLabel = NSTextField(wrappingLabelWithString: "")
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
		let container = DesktopSurface(DesktopTheme.sidebar)

		let brandRow = makeBrandRow()
		configureNewChatButton()
		let projectsHeader = makeProjectsHeader()

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
			14.5,
			after: brandRow
		)
		stack.setCustomSpacing(
			12,
			after: newChatButton
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 14
		)
		for row in [brandRow, projectsHeader]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		newChatButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		brandRow.heightAnchor.constraint(equalToConstant: 24).isActive = true
		newChatButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
	private var renderedPresentation: NavigationPresentation?
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
		guard previousPresentation != snapshot
		else
		{
			return
		}
		let nextUnreadThreadIDs = unreadTracker.observe(snapshot)
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
				|| projectDisplayNames != snapshot.projectDisplayNames
		if currentProject != nextProject
		{
			isCurrentProjectCollapsed = false
			projectTaskLimit = 5
		}
		currentProject = nextProject
		recentProjects = snapshot.recentProjects
		pinnedProjectPaths = snapshot.pinnedProjectPaths
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

		let activeState = renderTaskStatus(snapshot)
		renderThreadAvailability(
			snapshot,
			activeState: activeState
		)

		let shouldReloadSidebar =
			threads != snapshot.threads || selectedThreadID != snapshot.selectedThreadID
				|| activeThreadChanged || activeStateChanged || projectsChanged || unreadChanged
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

	private func renderThreadAvailability(
		_ snapshot: NavigationPresentation,
		activeState: ExecutionState?
	)
	{
		let waitingForThreadID = snapshot.executionState.isBusy && snapshot.activeThreadID == nil
		newChatButton.isEnabled = !waitingForThreadID && snapshot.selectedTaskWorkspaceID == nil
		currentProjectActiveTaskCount = activeState?.isBusy == true ? 1 : 0
		canStartProjectChat = newChatButton.isEnabled && activeState?.isBusy != true
		chatsTable.isEnabled = !waitingForThreadID
		canManageSelectedThread = snapshot.canManageThreads
		canManageSidebarTasks = snapshot.canManageThreads
		archiveButton.title = snapshot.showingArchived ? "Restore" : "Archive"
		archiveButton.toolTip = archiveButton.title
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
			let title = thread.name ?? thread.preview ?? thread.id
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
		onRefresh?()
	}

}
