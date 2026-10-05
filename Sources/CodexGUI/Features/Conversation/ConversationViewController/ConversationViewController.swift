import AppKit

// Stored AppKit state stays on the controller so its responsibility extensions share
// one selection, draft, and transcript lifecycle. Cross-file helpers use module access.
@MainActor
final class ConversationViewController: NSViewController,
	NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSTextViewDelegate,
	NSSearchFieldDelegate
{
	var onSelectSkill: ((AvailableSkill) -> Void)?
	var onSlashCommand: ((SlashCommandInvocation) -> Void)?
	var onSend: (() -> Void)?
	var onSteer: ((String) -> Void)?
	var onStop: (() -> Void)?
	var onReturnToActiveTask: (() -> Void)?
	var onDraftChange: ((String) -> Void)?
	var onAddContext: ((ComposerContextItem) -> Void)?
	var onImportImageContext: ((ComposerContextItem) -> Bool)?
	var onRemoveContext: ((String) -> Void)?
	var onReuseContext: ((String) -> Void)?
	var onSelectModel: ((String?) -> Void)?
	var onSelectEffort: ((String?) -> Void)?
	var onSetFastMode: ((Bool) -> Void)?
	var onSelectApprovalMode: ((ApprovalMode) -> Void)?
	var onInsertPath: (() -> Void)?
	var onLoadEarlierTurns: (() -> Void)?
	var onLoadEarlierTurnReferences: (() -> Void)?
	var onConversationViewportChanged: ((ConversationViewport) -> Void)?
	var viewportPublicationTask: Task<Void, Never>?
	var lastPublishedViewport: ConversationViewport?
	var onLoadTurnPreview: ((String) -> Void)?
	var onJumpToTurnReference: ((String) -> Void)?
	var onViewChanges: (() -> Void)?
	var onRespond: ((PendingInteraction, InteractionResponse) -> Void)?
	var onToggleBookmark: ((ConversationBookmark) -> Void)?
	var onJumpDisplayed: (() -> Void)?

	private let stateLabel = NSTextField(labelWithString: "Disconnected")
	private let activeTaskLabel = NSTextField(wrappingLabelWithString: "")
	private let returnToTaskButton = NSButton(
		title: "Return to Task",
		target: nil,
		action: nil
	)
	private let planButton = NSButton(
		title: "Plan",
		target: nil,
		action: nil
	)
	private let activityLabel = CurrentActionLabel(labelWithString: "")
	private var activePlan: TurnPlanUpdate?
	private var planPopover: NSPopover?
	let modelEffortButton = ModelEffortSelectionButton(
		title: "Select effort",
		target: nil,
		action: nil
	)
	var modelEffortPopover: ComposerPopoverPanel?
	var latestModelEffortSummary: String?
	var latestModelEffortTitle: String?
	var latestFastMode = false
	let modelEffortController = ModelEffortPopoverView()
	let approvalPolicyButton = NSButton(
		title: "Ask for approval",
		target: nil,
		action: nil
	)
	let approvalPolicyController = ApprovalPolicyPopoverView()
	var approvalPolicyPopover: NSPopover?
	var fullAccessConfirmationPanel: NSPanel?
	var approvalMode: ApprovalMode = .askForApproval
	let preferenceWarningLabel = NSTextField(wrappingLabelWithString: "")
	private var requestContextText = ""
	var collectionView = NSCollectionView()
	let loadEarlierButton = NSButton(
		title: "Load Earlier Messages",
		target: nil,
		action: nil
	)
	let conversationScrollView = NSScrollView()
	let turnNavigationRail = TurnNavigationRail()
	private var transcriptUtilityRow: NSStackView?
	private var centeredReadingRows: [(
		content: NSView,
		row: NSView,
		horizontalConstraints: [NSLayoutConstraint]
	)] = []
	private var paneResizeControlConstraints: [NSLayoutConstraint] = []
	private let emptyStateLabel = NSTextField(wrappingLabelWithString: "What can I help with?")
	let latestButton = NSButton(
		title: "Latest Message",
		target: nil,
		action: nil
	)
	let transcriptPreparation = TranscriptPreparationCoordinator()
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
	let composer = ContextComposerTextView()
	let composerScrollView = NSScrollView()
	let composerSurface = DesktopSurface(
		DesktopTheme.canvas,
		cornerRadius: 24,
		bordered: true
	)
	var composerHeightConstraint: NSLayoutConstraint?
	let contextView = ComposerContextView()
	lazy var attachmentDetailsScrollView = BoundedContentScrollView(views: [contextView])
	lazy var requestDetailsScrollView = BoundedContentScrollView(views: [interactionStack])
	let addContextButton = NSPopUpButton()
	let planModeLabel = NSTextField(labelWithString: "Plan mode")
	var fileSearchPopover: NSPopover?
	var fileSelectionReceiver: ((ComposerContextItem) -> Void)?
	var fileSearchField: NSSearchField?
	var fileResultsStack: NSStackView?
	var completionRange: NSRange?
	let slashCommandController = SlashCommandPopoverView()
	var slashCommandPopover: ComposerPopoverPanel?
	var slashCompletionRange: NSRange?
	var slashCompletionGeneration = 0
	var slashCompletionText: String?
	var fileSearchWasCompletion = false
	let fileIndexRuntime = ProjectFileIndexRuntime()
	let sendButton = NSButton(
		title: "Send",
		target: nil,
		action: nil
	)
	let steerButton = NSButton(
		title: "Steer",
		target: nil,
		action: nil
	)
	let stopButton = NSButton(
		title: "Stop",
		target: nil,
		action: nil
	)
	let interactionStack = NSStackView()
	var entries: [ConversationEntry] = []
	var displayedRows: [ConversationTranscriptRow] = []
	var replyActionEntryID: String?
	var collapsedGroupIDs = Set<String>()
	var expandedFileChangeIDs = Set<String>()
	var expandedActivityIDs = Set<String>()
	var activityOutputPositions: [
		String: ConversationActivityCollectionItem.OutputReadingPosition
	] =
		[:]
	var requestedTurnTimings: [ConversationTurnTiming] = []
	var turnStatusTimer: Timer?
	var transcriptIsVisible = true
	var timingExecutionState: ExecutionState = .disconnected
	var onOpenActivityFile: (String) -> Void =
	{
		NSWorkspace.shared.open(URL(fileURLWithPath: $0))
	}
	private var renderedInteractions: ConversationPresentation.Interactions?
	var expandedEntryIDs = Set<String>()
	var projectPath: String?
	var selectedThreadID: String?
	var selectionGeneration = 0
	var draftImageStore = DraftImageStore()
	var imageImportTasks: [UUID: Task<Void, Never>] = [:]
	var lastImageImportID: UUID?
	var composerSubmissionPresentation: ConversationPresentation.Composer?
	var bookmarks: [ConversationBookmark] = []
	var requestedJumpItemID: String?
	var pendingNavigationTurnID: String?
	var turnNavigationTask: Task<Void, Never>?
	var jumpAnimationRevision = 0
	var isAnimatingJump = false

	deinit
	{
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		for task in imageImportTasks.values
		{
			task.cancel()
		}
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		transcriptIsVisible = false
		activityLabel.presentationIsVisible = false
		turnStatusTimer?.invalidate()
		turnStatusTimer = nil
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		transcriptIsVisible = true
		activityLabel.presentationIsVisible = true
		updateTurnStatusTimer()
	}

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		let (activeTaskRow, progressRow) = configureTaskStatusControls()
		configurePreferenceControls()
		configureTranscriptControls()
		configureComposerControls()

		let composerArea = makeComposerArea()

		let headerStack = AppKitLayout.verticalStack(
			[stateLabel, activeTaskRow, progressRow, preferenceWarningLabel],
			spacing: 4
		)
		for row in [stateLabel, activeTaskRow, progressRow, preferenceWarningLabel]
		{
			row.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
		}
		let utilityRow = AppKitLayout.horizontalStack(
			[loadEarlierButton, flexibleSpace()],
			spacing: 6
		)
		// Reserve this row only while earlier-history navigation is available.
		utilityRow.heightAnchor.constraint(equalToConstant: 24).isActive = true
		// These rows only have content after a snapshot supplies it. Keep the
		// first fitting pass from reserving their empty heights.
		activeTaskRow.isHidden = true
		progressRow.isHidden = true
		utilityRow.isHidden = true
		transcriptUtilityRow = utilityRow
		let transcriptArea = makeTranscriptArea()
		installConversationStack(
			in: container,
			headerStack: headerStack,
			utilityRow: utilityRow,
			transcriptArea: transcriptArea,
			composerArea: composerArea
		)
		configureEmptyState(in: container)
		configureTurnNavigation(in: container)
		view = container
	}

	private func makeTranscriptArea() -> NSView
	{
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
		return transcriptArea
	}

	private func installConversationStack(
		in container: NSView,
		headerStack: NSStackView,
		utilityRow: NSStackView,
		transcriptArea: NSView,
		composerArea: NSStackView
	)
	{
		let stack = AppKitLayout.verticalStack(
			[
				centeredReadingRow(headerStack),
				centeredReadingRow(utilityRow),
				transcriptArea,
				centeredReadingRow(requestDetailsScrollView),
				centeredReadingRow(composerArea),
			],
			spacing: 6
		)
		stack.alignment = .leading
		container.addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 12
			),
			stack.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -12
			),
			stack.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 12
			),
			stack.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -20
			),
		])
		for row in stack.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		conversationScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
			.isActive = true
		conversationScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	private func configureEmptyState(in container: NSView)
	{
		emptyStateLabel.font = .systemFont(
			ofSize: 26,
			weight: .regular
		)
		emptyStateLabel.alignment = .center
		emptyStateLabel.lineBreakMode = .byWordWrapping
		emptyStateLabel.maximumNumberOfLines = 0
		emptyStateLabel.setAccessibilityLabel("Start a new conversation with Codex")
		emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(emptyStateLabel)
		NSLayoutConstraint.activate([
			emptyStateLabel.centerXAnchor.constraint(equalTo: conversationScrollView.centerXAnchor),
			emptyStateLabel.centerYAnchor.constraint(equalTo: conversationScrollView.centerYAnchor),
			emptyStateLabel.widthAnchor.constraint(
				equalTo: conversationScrollView.widthAnchor,
				constant: -32
			),
		])
	}

	private func configureTaskStatusControls() -> (NSStackView, NSStackView)
	{
		stateLabel.font = .systemFont(ofSize: 12)
		stateLabel.textColor = .secondaryLabelColor
		stateLabel.setAccessibilityLabel("Execution state")
		stateLabel.lineBreakMode = .byTruncatingTail
		stateLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		activeTaskLabel.font = .systemFont(ofSize: 12)
		activeTaskLabel.textColor = .secondaryLabelColor
		activeTaskLabel.maximumNumberOfLines = 1
		activeTaskLabel.lineBreakMode = .byTruncatingTail
		activeTaskLabel.setAccessibilityLabel("Active task location")
		returnToTaskButton.target = self
		returnToTaskButton.action = #selector(returnToActiveTask)
		returnToTaskButton.setAccessibilityLabel("Return to active task conversation")
		DesktopTheme.styleButton(
			returnToTaskButton,
			icon: .undo
		)
		planButton.target = self
		planButton.action = #selector(showPlan)
		planButton.setAccessibilityLabel("Show reported task plan")
		DesktopTheme.styleButton(
			planButton,
			icon: .notebookCheck
		)
		activityLabel.font = .systemFont(ofSize: 12)
		activityLabel.textColor = .secondaryLabelColor
		activityLabel.lineBreakMode = .byTruncatingTail
		activityLabel.setAccessibilityLabel("Reported task activity")
		let activeTaskRow = AppKitLayout.horizontalStack([activeTaskLabel, returnToTaskButton])
		activeTaskLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let progressRow = AppKitLayout.horizontalStack([planButton, activityLabel])
		activityLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		return (activeTaskRow, progressRow)
	}

	func flexibleSpace() -> NSView
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
		return spacer
	}

	private func centeredReadingRow(_ content: NSView) -> NSView
	{
		// The outer stack lays out full-width rows. Only each row's inner content is capped,
		// so the reading width cannot become the conversation pane's maximum width.
		let row = NSView()
		content.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(content)
		let preferredWidth = content.widthAnchor.constraint(equalTo: row.widthAnchor)
		// Yield to AppKit's window-resize priorities so the inner cap cannot limit the window.
		preferredWidth.priority = .defaultLow
		let horizontalConstraints = [
			content.centerXAnchor.constraint(equalTo: row.centerXAnchor),
			content.widthAnchor.constraint(
				lessThanOrEqualToConstant: ConversationFlowLayout.maximumContentWidth
			),
			content.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor),
			preferredWidth,
		]
		NSLayoutConstraint.activate(horizontalConstraints + [
			content.topAnchor.constraint(equalTo: row.topAnchor),
			content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
		])
		row.isHidden = content.isHidden
		centeredReadingRows.append((
			content: content,
			row: row,
			horizontalConstraints: horizontalConstraints
		))
		return row
	}

	func beginPaneResize()
	{
		guard !transcriptResizeReasons.contains(.pane)
		else
		{
			return
		}
		view.layoutSubtreeIfNeeded()
		beginTranscriptResize(reason: .pane)
		for entry in centeredReadingRows where !entry.row.isHidden
		{
			let frame = entry.content.frame
			NSLayoutConstraint.deactivate(entry.horizontalConstraints)
			paneResizeControlConstraints.append(contentsOf: [
				entry.content.widthAnchor.constraint(equalToConstant: frame.width),
				entry.content.leadingAnchor.constraint(
					equalTo: entry.row.leadingAnchor,
					constant: frame.minX
				),
			])
		}
		NSLayoutConstraint.activate(paneResizeControlConstraints)
	}

	func endPaneResize()
	{
		guard transcriptResizeReasons.contains(.pane)
		else
		{
			return
		}
		NSLayoutConstraint.deactivate(paneResizeControlConstraints)
		paneResizeControlConstraints.removeAll()
		for entry in centeredReadingRows
		{
			NSLayoutConstraint.activate(entry.horizontalConstraints)
		}
		view.layoutSubtreeIfNeeded()
		endTranscriptResize(reason: .pane)
	}

	func updateTranscriptUtilityRowVisibility()
	{
		transcriptUtilityRow?.isHidden = loadEarlierButton.isHidden
		updateReadingRowVisibility()
	}

	private func updateReadingRowVisibility()
	{
		for (content, row, _) in centeredReadingRows where row.isHidden != content.isHidden
		{
			row.isHidden = content.isHidden
		}
	}

	var renderedPresentation: ConversationPresentation?

	func render(_ snapshot: ConversationSnapshot)
	{
		render(ConversationPresentation(snapshot))
	}

	func render(_ snapshot: ConversationPresentation)
	{
		_ = view
		let previous = renderedPresentation
		guard previous != snapshot
		else
		{
			return
		}
		renderedPresentation = snapshot
		if previous?.owner != snapshot.owner
			|| previous?.composer.draftLifetime != snapshot.composer.draftLifetime
		{
			turnNavigationRail.dismissPreview()
			dismissSlashCommands()
			fileSearchPopover?.close()
			fileSelectionReceiver = nil
			configurePreferenceCallbacks()
			modelEffortPopover?.close()
			approvalPolicyPopover?.close()
			completionRange = nil
			selectionGeneration += 1
			cancelImageImports()
		}
		if previous?.owner != snapshot.owner
		{
			turnNavigationTask?.cancel()
			viewportPublicationTask?.cancel()
			lastPublishedViewport = nil
			cancelNavigationMotion()
			pendingNavigationTurnID = nil
			requestedJumpItemID = nil
			jumpAnimationRevision += 1
			isAnimatingJump = false
			turnNavigationRail.render([])
		}
		fileIndexRuntime.onChange =
		{
			[weak self] in
			self?.updateFileResults(query: self?.fileSearchField?.stringValue ?? "")
		}
		fileIndexRuntime.select(snapshot.owner)
		projectPath = snapshot.owner.projectPath
		selectedThreadID = snapshot.owner.selectedThreadID
		if previous?.navigation != snapshot.navigation
		{
			bookmarks = snapshot.navigation.bookmarks
			turnNavigationRail.canLoadEarlierReferences = snapshot.navigation
				.canLoadEarlierTurnReferences
			updateTurnNavigationSummaries(includeLoaded: previous?.owner == snapshot.owner)
			turnNavigationRail.refreshBookmark()
			refreshVisibleReplyActionBookmark()
		}
		if previous?.status != snapshot.status
		{
			timingExecutionState = snapshot.status.executionState
			renderTaskStatus(snapshot.status)
			updateTurnStatusTimer()
		}
		if previous?.requestContext != snapshot.requestContext
		{
			renderRequestContext(snapshot.requestContext)
		}
		if previous?.preferences != snapshot.preferences
		{
			preferenceWarningLabel.stringValue = snapshot.preferences.preferenceWarning ?? ""
			preferenceWarningLabel.isHidden = snapshot.preferences.preferenceWarning == nil
			renderModelAndApprovalPreferences(snapshot.preferences)
		}
		if previous?.transcript != snapshot.transcript
			|| previous?.status.executionState != snapshot.status.executionState
		{
			loadEarlierButton.isHidden = !snapshot.transcript.canLoadEarlierTurns
			updateTranscriptUtilityRowVisibility()
			emptyStateLabel.isHidden = !snapshot.transcript.entries.isEmpty
				|| snapshot.transcript.selectedThreadID != nil
			prepareTranscript(snapshot.transcript)
		}
		if previous?.composer != snapshot.composer
		{
			renderComposer(snapshot.composer)
		}
		if previous?.interactions != snapshot
			.interactions
		{
			renderInteractions(snapshot.interactions)
		}
		if previous?.requestContext != snapshot.requestContext
			|| previous?.composer != snapshot.composer || previous?.interactions != snapshot
			.interactions
		{
			requestDetailsScrollView.updateContentHeight()
		}
		updateReadingRowVisibility()
	}

	private func renderTaskStatus(_ snapshot: ConversationPresentation.Status)
	{
		stateLabel.stringValue = snapshot.statusMessage ?? snapshot.executionState.title
		stateLabel.toolTip = stateLabel.stringValue
		stateLabel.isHidden =
			snapshot.statusMessage == nil && snapshot.executionState != .disconnected
				&& snapshot.executionState != .failed
		let isViewingActiveTask =
			snapshot.activeThreadID != nil && snapshot.activeThreadID == snapshot.selectedThreadID
		let taskIsElsewhere = snapshot.activeExecutionState != nil && !isViewingActiveTask
		activeTaskLabel.stringValue =
			taskIsElsewhere
				? "\(snapshot.activeExecutionState?.title ?? "Task active") in another conversation"
				: ""
		activeTaskLabel.superview?.isHidden = !taskIsElsewhere
		returnToTaskButton.isEnabled = snapshot.activeThreadID != nil
		returnToTaskButton.isHidden = !taskIsElsewhere

		let updatedPlan = isViewingActiveTask ? snapshot.activePlan : nil
		if activePlan != updatedPlan
		{
			planPopover?.close()
		}
		activePlan = updatedPlan
		planButton.isHidden = activePlan == nil
		if let plan = activePlan
		{
			let finished = plan.plan.filter
			{
				$0.status == .completed
			}.count
			planButton.title = "Plan \(finished)/\(plan.plan.count)"
		}

		let jumpStatus = snapshot
			.jumpError ?? (snapshot.jumpLoading ? "Loading target message…" : "")
		activityLabel.stringValue = [
			isViewingActiveTask ? snapshot.activeActivity ?? "" : "",
			jumpStatus,
		]
		.filter
		{
			!$0.isEmpty
		}.joined(separator: " · ")
		activityLabel.toolTip = activityLabel.stringValue
		activityLabel.isHidden = activityLabel.stringValue.isEmpty
		activityLabel.superview?.isHidden = planButton.isHidden && activityLabel.isHidden
		activityLabel.actionIsActive = isViewingActiveTask
			&& snapshot.activeExecutionState?.isBusy == true
			&& !(snapshot.activeActivity ?? "").isEmpty
	}

	private func renderRequestContext(_ snapshot: ConversationPresentation.RequestContext)
	{
		let includedItemCount = snapshot.includedItemCount
		let skill = snapshot.selectedSkill
		let skillAvailable = snapshot.skillAvailable
		let contextSummaryParts = [
			includedItemCount == 0 ? nil : "\(includedItemCount) pinned item(s)",
			skill.map
			{
				"Skill \($0.invocationText)\(skillAvailable ? "" : " unavailable")"
			},
		].compactMap
		{
			$0
		}
		let contextDescription =
			contextSummaryParts.isEmpty
				? "Request Context: None…"
				: "Request Context: \(contextSummaryParts.joined(separator: " · "))…"
		addContextButton.toolTip = "Add attachments · \(contextDescription)"

		requestContextText = snapshot.includedContextText
		if !snapshot.draftContextSummary.isEmpty
		{
			requestContextText += "\n\nDraft context:\n" + snapshot.draftContextSummary
		}
		if let skill
		{
			requestContextText +=
				(requestContextText.isEmpty ? "" : "\n\n")
				+ "Selected skill for a new turn: \(skill.invocationText)\n\(skill.description)"
				+ (skillAvailable
					? "" :
					"\nUnavailable in the current backend skill list; it will not be invoked.")
				+ "\nSteering an active turn sends the editable draft "
				+ "and selected project context without this skill invocation."
		}
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		updateComposerHeight()
		attachmentDetailsScrollView.updateContentHeight()
		requestDetailsScrollView.updateContentHeight()
		updateReadingRowVisibility()
	}

	private func renderInteractions(_ presentation: ConversationPresentation.Interactions)
	{
		guard presentation != renderedInteractions
		else
		{
			return
		}
		renderedInteractions = presentation
		let interactions = presentation.values
		for view in interactionStack.arrangedSubviews
		{
			interactionStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		let respond = onRespond
		for interaction in interactions
		{
			let card = InteractionCardView(interaction: interaction)
			{
				response in respond?(interaction, response)
			}
			interactionStack.addArrangedSubview(card)
			card.widthAnchor.constraint(equalTo: interactionStack.widthAnchor).isActive = true
		}
		interactionStack.isHidden = interactions.isEmpty
	}

	@objc func inspectRequestContext()
	{
		guard let window = view.window
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = "Project Context for Next Request"
		alert.informativeText = "Review the selected context and skill invocation before sending."
		alert.accessoryView =
			ScrollableTextPreview.make(
				text: requestContextText.isEmpty
					? ("No pinned project context or skill is selected. "
						+ "The editable message is sent as written.")
					: requestContextText,
				size: NSSize(
					width: min(
						440,
						window.frame.width - 80
					),
					height: 240
				),
				font: .systemFont(ofSize: 13),
				accessibilityLabel: "Project context and skill invocation preview"
			).scrollView
		alert.addButton(withTitle: "Close")
		alert.beginSheetModal(for: window)
	}

	@objc private func returnToActiveTask()
	{
		onReturnToActiveTask?()
	}
	@objc private func showPlan()
	{
		guard let activePlan
		else
		{
			return
		}
		let lines = activePlan.plan.enumerated().map
		{
			index, step in
			let status: String
			switch step.status
			{
			case .pending: status = "Pending"
			case .inProgress: status = "In progress"
			case .completed: status = "Completed"
			}
			return "\(index + 1). \(step.step) — \(status)"
		}
		let explanation = activePlan.explanation.map
		{
			"\($0)\n\n"
		} ?? ""
		let previewSize = NSSize(
			width: 400,
			height: min(
				320,
				CGFloat(lines.count * 48 + 40)
			)
		)
		let preview = ScrollableTextPreview.make(
			text: explanation + lines.joined(separator: "\n\n"),
			size: previewSize,
			font: .systemFont(ofSize: 13),
			accessibilityLabel: "Reported task plan and step statuses"
		)
		preview.textView.drawsBackground = false
		preview.textView.textContainerInset = NSSize(
			width: 12,
			height: 12
		)
		let controller = NSViewController()
		controller.view = preview.scrollView
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.contentSize = previewSize
		popover.behavior = .transient
		planPopover = popover
		popover.show(
			relativeTo: planButton.bounds,
			of: planButton,
			preferredEdge: .maxY
		)
	}

}
