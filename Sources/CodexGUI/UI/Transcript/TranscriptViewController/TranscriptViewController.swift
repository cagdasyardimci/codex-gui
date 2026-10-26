import AppKit

/// Owns transcript rendering, navigation, and reading position for each presentation owner.
@MainActor
final class TranscriptViewController: NSViewController,
	NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout
{
	var onLoadEarlierTurns: (() -> Void)?
	var onLoadEarlierTurnReferences: (() -> Void)?
	var onConversationViewportChanged: ((ConversationViewport) -> Void)?
	var onLoadTurnPreview: ((String) -> Void)?
	var onJumpToTurnReference: ((String) -> Void)?
	var onViewChanges: (() -> Void)?
	var onOpenSubagents: (() -> Void)?
	var onSelectSubagentThread: ((String) -> Void)?
	var onToggleBookmark: ((ConversationBookmark) -> Void)?
	var onJumpDisplayed: (() -> Void)?
	var onUtilityRowVisibilityChanged: (() -> Void)?
	var onOpenActivityFile: (String) -> Void =
	{
		NSWorkspace.shared.open(URL(fileURLWithPath: $0))
	}

	var renderedPresentation: TranscriptPresentation?
	var collectionView = NSCollectionView()
	let loadEarlierButton = DesktopStyledButton(
		title: "Load Earlier Messages",
		target: nil,
		action: nil
	)
	let conversationScrollView = NSScrollView()
	let turnNavigationRail = TurnNavigationRail()
	let latestButton = DesktopNativeIconButton(
		title: "Latest Message",
		label: "Return to latest message",
		icon: .arrowDown
	)
	lazy var utilityRow = makeTranscriptUtilityRow()
	let transcriptPreparation: TranscriptPreparationCoordinator
	var preparedContents: [String: PreparedConversationContent] = [:]
	struct MeasuredItemSize
	{
		let content: PreparedConversationContent
		let kind: ConversationEntryKind
		let expandable: Bool
		let imageAttachmentCount: Int
		let showsReplyActions: Bool
		let size: NSSize
	}
	var measuredItemSizes: [String: MeasuredItemSize] = [:]
	var liveResizeInProgress = false
	enum TranscriptResizeReason
	{
		case window, pane
	}
	var transcriptResizeReasons = Set<TranscriptResizeReason>()
	var liveResizeVisibleIDs = Set<String>()
	var needsFinalResizeMetrics = false
	var resizeFollowingOutput = false
	var resizeReadingAnchor: ReadingAnchor?
	var resizeContext: String?
	var visibleResizeRefreshTimer: Timer?
	var widthChangeReadingPosition: WidthChangeReadingPosition?
	var widthChangeRestoreTask: Task<Void, Never>?
	var restoringWidthChangeReadingPosition = false
	var requestedEntries: [ConversationEntry] = []
	var renderedContext: String?
	var requestedContext: String?
	var entries: [ConversationEntry] = []
	var displayedRows: [ConversationTranscriptRow] = []
	var replyActionEntryID: String?
	var expandedTurnIDs = Set<String>()
	var expandedFileChangeIDs = Set<String>()
	var workEntryIDsByTurn: [String: Set<String>] = [:]
	var expandedGroupIDs = Set<String>()
	var collapsedImageIDs = Set<String>()
	var expandedActivityIDs = Set<String>()
	var activityOutputPositions: [
		String: ConversationActivityCollectionItem.OutputReadingPosition
	] = [:]
	var requestedTurnTimings: [ConversationTurnTiming] = []
	var turnStatusTimer: Timer?
	var transcriptIsVisible = true
	var timingExecutionState: ExecutionState = .disconnected
	var expandedEntryIDs = Set<String>()
	var projectPath: String?
	var selectedThreadID: String?
	var selectionGeneration = 0
	var bookmarks: [ConversationBookmark] = []
	var requestedJumpItemID: String?
	var pendingNavigationTurnID: String?
	var turnNavigationTask: Task<Void, Never>?
	var viewportPublicationTask: Task<Void, Never>?
	var lastPublishedViewport: ConversationViewport?
	// The owned motion task can be captured and awaited after cancellation retires it.
	var jumpAnimationCompletion: Task<Void, Never>?
	var jumpAnimationRevision = 0
	var isAnimatingJump = false
	var shouldReduceMotion: () -> Bool =
	{
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	init(transcriptPreparation: TranscriptPreparationCoordinator =
		TranscriptPreparationCoordinator())
	{
		self.transcriptPreparation = transcriptPreparation
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	deinit
	{
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		jumpAnimationCompletion?.cancel()
		widthChangeRestoreTask?.cancel()
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		cancelNavigationMotion()
		transcriptIsVisible = false
		visibleResizeRefreshTimer?.invalidate()
		visibleResizeRefreshTimer = nil
		turnStatusTimer?.invalidate()
		turnStatusTimer = nil
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		transcriptIsVisible = true
		updateTurnStatusTimer()
	}

	override func loadView()
	{
		configureTranscriptControls()
		let transcriptArea = NSView()
		transcriptArea.addSubview(conversationScrollView)
		transcriptArea.addSubview(latestButton)
		conversationScrollView.translatesAutoresizingMaskIntoConstraints = false
		latestButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			conversationScrollView.leadingAnchor.constraint(equalTo: transcriptArea.leadingAnchor),
			conversationScrollView.trailingAnchor
				.constraint(equalTo: transcriptArea.trailingAnchor),
			conversationScrollView.topAnchor.constraint(equalTo: transcriptArea.topAnchor),
			conversationScrollView.bottomAnchor.constraint(equalTo: transcriptArea.bottomAnchor),
			latestButton.centerXAnchor.constraint(equalTo: conversationScrollView.centerXAnchor),
			latestButton.bottomAnchor.constraint(
				equalTo: conversationScrollView.bottomAnchor,
				constant: -12
			),
		])
		transcriptArea.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		conversationScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
			.isActive = true
		conversationScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		view = transcriptArea
	}

	private func makeTranscriptUtilityRow() -> NSStackView
	{
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		spacer.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let row = AppKitLayout.horizontalStack(
			[loadEarlierButton, spacer],
			spacing: 6
		)
		row.heightAnchor.constraint(equalToConstant: 24).isActive = true
		row.isHidden = true
		return row
	}

	func render(_ presentation: TranscriptPresentation)
	{
		_ = view
		let previous = renderedPresentation
		guard previous != presentation
		else
		{
			return
		}
		if previous?.owner != presentation.owner
		{
			resetTranscriptNavigation()
		}
		if previous?.owner != presentation.owner
			|| previous?.interactionRevision != presentation.interactionRevision
		{
			selectionGeneration += 1
		}
		renderedPresentation = presentation
		projectPath = presentation.owner.projectPath
		selectedThreadID = presentation.selectedThreadID
		bookmarks = presentation.navigation?.bookmarks ?? []
		turnNavigationRail.canLoadEarlierReferences =
			presentation.navigation?.canLoadEarlierTurnReferences ?? false
		if previous?.navigation != presentation.navigation
			|| previous?.owner != presentation.owner
		{
			updateTurnNavigationSummaries(includeLoaded: previous?.owner == presentation.owner)
			turnNavigationRail.refreshBookmark()
			refreshVisibleReplyActionBookmark()
		}
		timingExecutionState = presentation.executionState
		loadEarlierButton.isHidden = !presentation.canLoadEarlierTurns
		updateTranscriptUtilityRowVisibility()
		if previous?.entries != presentation.entries
			|| previous?.turnTimings != presentation.turnTimings
			|| previous?.owner != presentation.owner
			|| previous?.executionState != presentation.executionState
			|| previous?.activeThreadID != presentation.activeThreadID
			|| previous?.activeTurnID != presentation.activeTurnID
		{
			prepareTranscript(presentation)
		}
		updateTurnStatusTimer()
	}

	func resetTranscriptNavigation()
	{
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		lastPublishedViewport = nil
		cancelNavigationMotion()
		pendingNavigationTurnID = nil
		requestedJumpItemID = nil
		turnNavigationRail.dismissPreview()
		turnNavigationRail.render([])
	}

	func setLoadEarlierEnabled(_ enabled: Bool)
	{
		loadEarlierButton.isEnabled = enabled
	}

	func beginPaneResize()
	{
		beginTranscriptResize(reason: .pane)
	}

	func endPaneResize()
	{
		endTranscriptResize(reason: .pane)
	}

	func updateTranscriptUtilityRowVisibility()
	{
		let hidden = loadEarlierButton.isHidden
		guard utilityRow.isHidden != hidden
		else
		{
			return
		}
		utilityRow.isHidden = hidden
		onUtilityRowVisibilityChanged?()
	}
}
