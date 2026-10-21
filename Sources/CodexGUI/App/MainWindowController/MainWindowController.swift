import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate
{
	private let sourceStore: WorkspaceStateStore
	let coordinator: TaskWorkspaceCoordinator?
	var currentStore: WorkspaceStateStore
	{
		coordinator?.selectedStore ?? sourceStore
	}
	private var publicationObserver: WorkspacePublicationCoordinator?
	// These members are shared by the action-binding and toolbar extensions.
	let onOpenProjectRequest: () -> Void
	let onInsertPathRequest: () -> Void
	let navigation = NavigationViewController()
	let conversation = ConversationViewController()
	let inspector = InspectorViewController()
	let files: FilesViewController
	var onFileDiscardDecision: (([UUID], FileViewerFailure?) -> Bool)?
	var filesProjectPath: String?
	var filesWereOpened = false
	var filesCloseApproved = false
	var filesCloseInProgress = false
	var fileCloseRequests: Set<UUID> = []
	var fileCloseQueue: [UUID] = []
	var fileClosePumpRunning = false
	var fileClosePumpTask: Task<Void, Never>?
	var fileSettlementTask: Task<Bool, Never>?
	var pendingFileSearch: PendingFileSearch?
	var onFileSearchPresented: ((PendingFileSearch) -> Void)?
	enum PendingFileSearch
	{
		case filename, content
	}
	var gitSummary = GitSummaryReconciliation()
	let summaryGitLoader = GitSummaryBackgroundLoader()
	private var toolbarVisibilityBeforeGitReview: Bool?
	private let windowButtonAlignment = NativeWindowButtonAlignment()
	let commandPalette = CommandPaletteController()
	let messageSearch = MessageSearchController()
	var messageSearchStoreIdentity: ObjectIdentifier?
	var messageSearchOwner: WorkspaceLifecycleOwnerReference?
	let settings = SettingsWindowController()
	let statusView = StatusPopoverView(frame: .zero)
	let statusButton = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	let titleLabel = NSTextField(labelWithString: "New chat")
	let titleContainer = NSView()
	let toolsToolbar = ToolsToolbarCoordinator()
	var statusPopover: NSPopover?
	let paneController: WindowPaneController
	var summaryChangesProvider: ((FeaturePresentationOwner) -> SummarySection<SummaryChangeTotals>)?
	var summaryVisibility = PinnedSummaryVisibility()
	var summaryReconciliation = ContextSummaryReconciliation()
	var subagentConversationSession: SubagentConversationSession?
	let summaryToggleButton = PinnedSummaryToggleButton(
		title: "",
		target: nil,
		action: nil
	)
	var latestSnapshot: ConversationSnapshot?
	var onSnapshot: ((ConversationSnapshot) -> Void)?

	init(
		store: WorkspaceStateStore,
		onOpenProject: @escaping () -> Void,
		onInsertPath: @escaping () -> Void,
		layoutStore: WindowLayoutStore? = nil,
		coordinator: TaskWorkspaceCoordinator? = nil,
		filesRuntime: FileViewerRuntime = FileViewerRuntime()
	)
	{
		self.sourceStore = store
		self.onOpenProjectRequest = onOpenProject
		self.onInsertPathRequest = onInsertPath
		self.coordinator = coordinator
		self.files = FilesViewController(runtime: filesRuntime)
		let window = Self.makeWindow()

		paneController = WindowPaneController(
			navigation: navigation,
			conversation: conversation,
			inspector: inspector,
			layoutStore: layoutStore
		)
		super.init(window: window)
		window.delegate = self
		shouldCascadeWindows = false
		configureInspectorCallbacks()
		configureFilesIntegration()
		configureToolbarControls()

		// AppKit requires a tracked split view to belong to the window before its toolbar appears.
		window.contentViewController = WindowChromeViewController(
			split: paneController.split,
			accountButton: statusButton
		)
		installConversationToolbar(in: window)
		windowButtonAlignment.update(in: window)
		updateMinimumWindowSize()
		observeWindowChrome(in: window)
		paneController.restoreLayout(in: window)
		observeWorkspacePublications()
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(windowDidClose),
			name: NSWindow.willCloseNotification,
			object: window
		)
	}

	private static func makeWindow() -> DesktopWindow
	{
		let window = DesktopWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 760
			),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Codex GUI"
		window.acceptsMouseMovedEvents = true
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.titlebarSeparatorStyle = .none
		window.toolbarStyle = .unifiedCompact
		window.backgroundColor = AppKitColorTokens.chrome
		window.center()

		return window
	}

	private func configureInspectorCallbacks()
	{
		inspector.onDetailGeometryChange =
		{
			[weak self] wide in self?.paneController.setWorkspaceFilesExpanded(wide)
		}
		inspector.onGitReviewDisplayChange =
		{
			[weak self] focused in self?.setGitReviewFocused(focused)
		}
		inspector.gitChanges.onToggleExpanded =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.inspector.setGitReviewFocused(!self.paneController.isGitReviewFocused)
		}
		inspector.gitChanges.onTogglePanel =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.inspector.setGitReviewFocused(!self.paneController.isGitReviewFocused)
		}
	}

	private func installConversationToolbar(in window: NSWindow)
	{
		// Tools composition belongs to this window; a shared identifier synchronizes other windows.
		let identifier = NSToolbar.Identifier("CodexGUIConversationToolbar.\(UUID().uuidString)")
		let toolbar = NSToolbar(identifier: identifier)
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.sizeMode = .small
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		window.toolbar = toolbar
	}

	private func observeWindowChrome(in window: NSWindow)
	{
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(windowChromeDidUpdate),
			name: NSWindow.didUpdateNotification,
			object: window
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(windowChromeDidUpdate),
			name: NSSplitView.didResizeSubviewsNotification,
			object: paneController.split.splitView
		)
	}

	private func observeWorkspacePublications()
	{
		if let coordinator
		{
			coordinator.onChange =
			{
				[weak self] in
				self?.renderSnapshot($0)
			}
			renderSnapshot(coordinator.currentSnapshot)
		}
		else
		{
			publicationObserver = WorkspacePublicationCoordinator(
				store: sourceStore,
				render:
				{
					[weak self] in self?.renderSnapshot($0)
				},
				command:
				{
					[weak self] command in
					self?.handlePresentationCommand(command)
				}
			)
		}
	}

	func renderSnapshot(_ snapshot: ConversationSnapshot)
	{
		self.latestSnapshot = snapshot
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		configureNavigationActions(target: target)
		configureSettingsAndStatusActions(target: target)
		configureInspectorActions(target: target)
		updateFilesProject(target: target)
		configureMessageSearchActions(target: target)
		configureConversationActions(target: target)

		updateConversationTitle(snapshot)

		renderWorkspaceStatus(
			snapshot,
			target: target
		)

		self.navigation.render(NavigationPresentation(snapshot))
		self.conversation.render(ConversationPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity
		))
		configureGitSummary(
			target: target,
			snapshot: snapshot
		)
		self.inspector.render(ReviewPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity
		))
		renderPinnedSummary(
			snapshot,
			target: target
		)
		self.inspector.changes.render(ReviewPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity
		))

		self.messageSearch.render(
			snapshot.messageSearch,
			loading: snapshot.searchLoading,
			unavailableReason: snapshot.searchError
		)

		if let target = snapshot.pendingJumpItemID
		{
			self.conversation.jumpToEntry(id: target)
		}
		self.onSnapshot?(snapshot)
	}

	private func updateConversationTitle(_ snapshot: ConversationSnapshot)
	{
		let selectedThread = snapshot.threads.first
		{
			$0.id == snapshot.selectedThreadID
		}
		let title = selectedThread?.displayTitle ?? "New chat"
		self.titleLabel.stringValue = title
		self.titleLabel.toolTip = title
		self.inspector.toolsTabs.setConversationTitle(title)
		self.window?.title = "\(title) — Codex GUI"
	}

	private func renderWorkspaceStatus(
		_ snapshot: ConversationSnapshot,
		target: WorkspaceIntentTarget
	)
	{
		let status = WorkspaceStatusPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity
		)
		self.settings.render(status)
		self.statusView.render(status)
		let executionTitle = status.execution.title
		self.statusButton.toolTip = "\(status.accountDescription) · \(executionTitle)"
		self.statusButton
			.setAccessibilityLabel("\(executionTitle). Open account and backend status")
	}

	private func setGitReviewFocused(_ focused: Bool)
	{
		paneController.setGitReviewFocused(focused)
		(window?.contentViewController as? WindowChromeViewController)?.setGitReviewFocused(focused)
		if focused
		{
			if toolbarVisibilityBeforeGitReview == nil
			{
				toolbarVisibilityBeforeGitReview = window?.toolbar?.isVisible
			}
			window?.toolbar?.isVisible = false
		}
		else
		{
			if let visible = toolbarVisibilityBeforeGitReview
			{
				window?.toolbar?.isVisible = visible
				toolbarVisibilityBeforeGitReview = nil
			}
			if inspector.isShowingDetails, inspector.panels.destination == .changes
			{
				paneController.setReviewCollapsed(false)
			}
		}
	}

	@objc private func windowDidClose()
	{
		Task
		{
			_ = await files.runtime.shutdown()
		}
		subagentConversationSession?.invalidate()
		subagentConversationSession = nil
		inspector.setGitReviewFocused(false)
		inspector.gitChanges.close()
		summaryGitLoader.cancel()
		publicationObserver?.cancel()
		publicationObserver = nil
		coordinator?.onChange = nil
		messageSearch.dismiss()
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool
	{
		if filesCloseApproved
		{
			filesCloseApproved = false
			return true
		}
		if files.runtime.state.documents.allSatisfy(
			{
				!$0.isDirty && !$0.isSaving
			}
		)
		{
			return true
		}
		guard !filesCloseInProgress
		else
		{
			return false
		}
		filesCloseInProgress = true
		Task
		{
			[weak self, weak sender] in
			guard let self
			else
			{
				return
			}
			let canClose = await self.settleFileWritesForClosing()
			self.filesCloseInProgress = false
			if canClose, let sender
			{
				self.filesCloseApproved = true
				sender.performClose(nil)
			}
		}
		return false
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func showWindow(_ sender: Any?)
	{
		super.showWindow(sender)
		// Toolbar attachment changes chrome height while preserving the content minimum.
		// Apply the supported full-window minimum after the toolbar has been laid out.
		window?.layoutIfNeeded()
		updateMinimumWindowSize()
		paneController.didPresentWindow()
	}

	@objc private func windowChromeDidUpdate()
	{
		if let window
		{
			windowButtonAlignment.update(in: window)
		}
		updateMinimumWindowSize()
		updateToolsToolbarControls()
	}

	private func updateMinimumWindowSize()
	{
		guard let window
		else
		{
			return
		}
		let chromeHeight = max(
			0,
			window.frame.height - window.contentLayoutRect.height
		)
		let minimumContentSize = NSSize(
			width: 800,
			height: max(
				1,
				500 - chromeHeight
			)
		)
		guard window.contentMinSize != minimumContentSize
		else
		{
			return
		}
		window.contentMinSize = minimumContentSize
	}

	func insertPath(
		_ path: String,
		target: WorkspaceIntentTarget? = nil
	)
	{
		if let target, !target.accepts(.editDraft(""))
		{
			return
		}
		conversation.insertPath(path)
	}
	func focusSearch()
	{
		paneController.setSidebarCollapsed(false)
		navigation.focusSearch()
	}

	func dispatchCurrent(_ intent: WorkspaceIntent)
	{
		let snapshot = coordinator?.currentSnapshot ?? sourceStore.currentSnapshot
		WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		.dispatch(intent)
	}

	func openProject(_ url: URL)
	{
		dispatchCurrent(.openProject(url))
	}

	func createTask()
	{
		navigation.presentNewTask()
	}

	func saveLayout()
	{
		paneController.saveLayout()
	}
}
