import AppKit

// The conversation owns its composer and execution controls; the child transcript
// owns message preparation, scrolling, selection, and navigation.
@MainActor
final class ConversationViewController: NSViewController,
	NSTextViewDelegate, NSSearchFieldDelegate
{
	let transcript: TranscriptViewController

	var onSelectSkill: ((AvailableSkill) -> Void)?
	var onRemoveSkill: ((ProjectSkillSelection) -> Void)?
	var onSlashCommand: ((SlashCommandInvocation) -> Void)?
	var onSend: (() -> Void)?
	var onRetryLockedChat: (() -> Void)?
	var onForkLockedChat: (() -> Void)?
	var onSteer: ((String) -> Void)?
	var onStop: (() -> Void)?
	var onReturnToActiveTask: (() -> Void)?
	var onDraftChange: ((String) -> Void)?
	var onAddContext: ((ComposerContextItem) -> Void)?
	var onImportImageContext: ((ComposerContextItem) -> Bool)?
	var onRemoveContext: ((String) -> Void)?
	var onSelectModel: ((String?) -> Void)?
	var onSelectEffort: ((String?) -> Void)?
	var onSetFastMode: ((Bool) -> Void)?
	var onSelectApprovalMode: ((ApprovalMode) -> Void)?
	var onInsertPath: (() -> Void)?
	var onLoadEarlierTurns: (() -> Void)?
	{
		didSet
		{
			transcript.onLoadEarlierTurns = onLoadEarlierTurns
		}
	}
	var onLoadEarlierTurnReferences: (() -> Void)?
	{
		didSet
		{
			transcript.onLoadEarlierTurnReferences = onLoadEarlierTurnReferences
		}
	}
	var onConversationViewportChanged: ((ConversationViewport) -> Void)?
	{
		didSet
		{
			transcript.onConversationViewportChanged = onConversationViewportChanged
		}
	}
	var onLoadTurnPreview: ((String) -> Void)?
	{
		didSet
		{
			transcript.onLoadTurnPreview = onLoadTurnPreview
		}
	}
	var onJumpToTurnReference: ((String) -> Void)?
	{
		didSet
		{
			transcript.onJumpToTurnReference = onJumpToTurnReference
		}
	}
	var onViewChanges: (() -> Void)?
	{
		didSet
		{
			transcript.onViewChanges = onViewChanges
		}
	}
	var onOpenSubagents: (() -> Void)?
	{
		didSet
		{
			transcript.onOpenSubagents = onOpenSubagents
		}
	}
	var onSelectSubagentThread: ((String) -> Void)?
	{
		didSet
		{
			transcript.onSelectSubagentThread = onSelectSubagentThread
		}
	}
	var onRespond: ((PendingInteraction, InteractionResponse) -> Void)?
	var onToggleBookmark: ((ConversationBookmark) -> Void)?
	{
		didSet
		{
			transcript.onToggleBookmark = onToggleBookmark
		}
	}
	var onJumpDisplayed: (() -> Void)?
	{
		didSet
		{
			transcript.onJumpDisplayed = onJumpDisplayed
		}
	}

	private let returnToTaskButton = DesktopStyledButton(
		title: "Return to Task",
		target: nil,
		action: nil
	)
	private let planButton = DesktopStyledButton(
		title: "Plan",
		target: nil,
		action: nil
	)
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
	let approvalPolicyButton = ComposerPermissionButton(
		title: "Ask for approval",
		target: nil,
		action: nil
	)
	let approvalPolicyController = ApprovalPolicyPopoverView()
	var approvalPolicyPopover: ComposerPopoverPanel?
	var fullAccessConfirmationPanel: NSPanel?
	var approvalMode: ApprovalMode = .askForApproval
	var hasConfiguredPermissions = false
	private var requestContextText = ""
	private var centeredReadingRows: [(
		content: NSView,
		row: NSView,
		horizontalConstraints: [NSLayoutConstraint]
	)] = []
	private var paneResizeControlConstraints: [NSLayoutConstraint] = []
	let composer = ContextComposerTextView()
	let chatLockView = ConversationLockView()
	let composerScrollView = NSScrollView()
	let composerSurface = DesktopSurface(
		AppKitColorTokens.composer,
		cornerRadius: ShapeTokens.Composer.cornerRadius,

		shadows: ShadowTokens.composer
	)
	let turnChangeSummaryButton = TurnChangeSummaryButton()
	let turnChangeSummaryLoader = ConversationTurnChangeSummaryLoader()
	var composerHeightConstraint: NSLayoutConstraint?
	let contextView = ComposerContextView()
	lazy var attachmentDetailsScrollView = BoundedContentScrollView(views: [contextView])
	var isPublishingComposerEdit = false
	lazy var requestDetailsScrollView = BoundedContentScrollView(views: [interactionStack])
	let addContextButton = DesktopPopupButton()
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
	let sendButton = ComposerSubmissionButton(role: .send)
	let steerButton = ComposerSubmissionButton(role: .steer)
	let stopButton = ComposerSubmissionButton(role: .stop)
	let interactionStack = NSStackView()
	private var renderedInteractions: ConversationPresentation.Interactions?
	var projectPath: String?
	var selectionGeneration = 0
	var draftImageStore = DraftImageStore()
	var imageImportTasks: [UUID: Task<Void, Never>] = [:]
	var lastImageImportID: UUID?
	var composerSubmissionPresentation: ConversationPresentation.Composer?

	init(transcriptPreparation: TranscriptPreparationCoordinator =
		TranscriptPreparationCoordinator())
	{
		transcript = TranscriptViewController(transcriptPreparation: transcriptPreparation)
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
		for task in imageImportTasks.values
		{
			task.cancel()
		}
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		turnChangeSummaryLoader.stop()
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		if let composerSubmissionPresentation
		{
			turnChangeSummaryLoader.render(
				request: composerSubmissionPresentation.turnChangeRequest,
				activeTurnID: composerSubmissionPresentation.activeTurnID
			)
		}
	}

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.canvas)
		let (activeTaskRow, progressRow) = configureTaskStatusControls()
		configurePreferenceControls()
		configureComposerControls()
		addChild(transcript)
		configureTranscriptCallbacks()

		let composerArea = makeComposerArea()

		let headerStack = AppKitLayout.verticalStack(
			[activeTaskRow, progressRow],
			spacing: 4
		)
		for row in [activeTaskRow, progressRow]
		{
			row.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
		}
		let utilityRow = transcript.utilityRow
		// These rows only have content after a snapshot supplies it. Keep the
		// first fitting pass from reserving their empty heights.
		activeTaskRow.isHidden = true
		progressRow.isHidden = true
		let transcriptArea = transcript.view
		installConversationStack(
			in: container,
			headerStack: headerStack,
			utilityRow: utilityRow,
			transcriptArea: transcriptArea,
			composerArea: composerArea
		)
		transcript.configureTurnNavigation(in: container)
		view = container
	}

	private func configureTranscriptCallbacks()
	{
		transcript.onUtilityRowVisibilityChanged =
		{
			[weak self] in self?.updateReadingRowVisibility()
		}
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
				constant: -LayoutTokens.Composer.paneBottomInset
			),
		])
		for row in stack.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		transcript.conversationScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	private func configureTaskStatusControls() -> (NSStackView, NSStackView)
	{
		returnToTaskButton.target = self
		returnToTaskButton.action = #selector(returnToActiveTask)
		returnToTaskButton.setAccessibilityLabel("Return to active task conversation")
		returnToTaskButton.symbol = .undo
		planButton.target = self
		planButton.action = #selector(showPlan)
		planButton.setAccessibilityLabel("Show reported task plan")
		planButton.symbol = .notebookCheck
		let activeTaskRow = AppKitLayout.horizontalStack([returnToTaskButton])
		let progressRow = AppKitLayout.horizontalStack([planButton])

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
		preferredWidth.priority = NSLayoutConstraint.Priority(749)
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
		guard !transcript.transcriptResizeReasons.contains(.pane)
		else
		{
			return
		}
		view.layoutSubtreeIfNeeded()
		transcript.beginPaneResize()
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
		guard transcript.transcriptResizeReasons.contains(.pane)
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
		transcript.endPaneResize()
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
			isPublishingComposerEdit = false
			transcript.turnNavigationRail.dismissPreview()
			dismissSlashCommands()
			fileSearchPopover?.close()
			fileSelectionReceiver = nil
			configurePreferenceCallbacks()
			modelEffortPopover?.close()
			approvalPolicyPopover?.close()
			completionRange = nil
			composer.undoManager?.removeAllActions()
			selectionGeneration += 1
			cancelImageImports()
		}
		fileIndexRuntime.onChange =
		{
			[weak self] in
			self?.updateFileResults(query: self?.fileSearchField?.stringValue ?? "")
		}
		fileIndexRuntime.select(snapshot.owner)
		projectPath = snapshot.owner.projectPath
		if previous?.status != snapshot.status
		{
			renderTaskStatus(snapshot.status)
		}
		if previous?.requestContext != snapshot.requestContext
		{
			renderRequestContext(snapshot.requestContext)
		}
		if previous?.preferences != snapshot.preferences
		{
			renderModelAndApprovalPreferences(snapshot.preferences)
		}
		transcript.render(TranscriptPresentation(
			owner: snapshot.owner,
			entries: snapshot.transcript.entries,
			turnTimings: snapshot.transcript.turnTimings,
			canLoadEarlierTurns: snapshot.transcript.canLoadEarlierTurns,
			navigation: TranscriptPresentation.Navigation(
				turnReferences: snapshot.navigation.turnReferences,
				turnPreviews: snapshot.navigation.turnPreviews,
				turnPreviewErrors: snapshot.navigation.turnPreviewErrors,
				canLoadEarlierTurnReferences: snapshot.navigation.canLoadEarlierTurnReferences,
				bookmarks: snapshot.navigation.bookmarks
			),
			executionState: snapshot.status.executionState,
			activeThreadID: snapshot.transcript.activeThreadID,
			activeTurnID: snapshot.transcript.activeTurnID,
			interactionRevision: selectionGeneration
		))
		if previous?.composer != snapshot.composer
		{
			renderComposer(snapshot.composer)
		}
		if !isPublishingComposerEdit
		{
			composer.renderSkill(
				snapshot.requestContext.selectedSkill,
				title: snapshot.requestContext.selectedSkillTitle
			)
			updateComposerHeight()
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

	func jumpToEntry(id: String)
	{
		transcript.jumpToEntry(id: id)
	}

	func waitForRendering() async
	{
		await transcript.waitForRendering()
	}

	private func renderTaskStatus(_ snapshot: ConversationPresentation.Status)
	{
		let isViewingActiveTask =
			snapshot.activeThreadID != nil && snapshot.activeThreadID == snapshot.selectedThreadID
		let taskIsElsewhere = snapshot.activeExecutionState != nil && !isViewingActiveTask
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
	}

	private func renderRequestContext(_ snapshot: ConversationPresentation.RequestContext)
	{
		let includedItemCount = snapshot.includedItemCount
		let skill = snapshot.selectedSkill
		let contextSummaryParts = [
			includedItemCount == 0 ? nil : "\(includedItemCount) pinned item(s)",
			skill.map
			{
				"Skill \($0.invocationText)"
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
		let interactions = presentation.values.filter
		{
			if case .unsupported = $0.kind
			{
				return false
			}
			return true
		}
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
