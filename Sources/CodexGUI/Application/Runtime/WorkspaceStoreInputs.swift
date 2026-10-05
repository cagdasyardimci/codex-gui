import Foundation

/// Captures scoped user inputs; authoritative values and work remain in the store.
@MainActor
struct WorkspaceStoreInputs
{
	let store: WorkspaceStateStore
	private var workspaceStore: WorkspaceStateStore
	{
		store
	}
	private var selectors: WorkspaceSelectors
	{
		WorkspaceSelectors(
			model: store.model,
			now: store.now()
		)
	}
	private var threads: [ThreadSummary]
	{
		selectors.threads
	}
	private var selectedThreadID: String?
	{
		selectors.selectedThreadID
	}
	private var activeThreadID: String?
	{
		selectors.activeThreadID
	}
	private var projectContext: ProjectContext
	{
		selectors.projectContext
	}
	private var pendingJumpThreadID: String?
	{
		selectors.pendingJumpThreadID
	}
	private var pendingJumpItemID: String?
	{
		selectors.pendingJumpItemID
	}
	private var jumpLoading: Bool
	{
		selectors.jumpLoading
	}
	private var jumpError: String?
	{
		selectors.jumpError
	}
	private var searchLoading: Bool
	{
		selectors.searchLoading
	}
	private var searchError: String?
	{
		selectors.searchError
	}
	private var composerDraft: ComposerDraft
	{
		selectors.composerDraft
	}
	private var draft: String
	{
		selectors.draft
	}
	private var draftContext: [ComposerContextItem]
	{
		selectors.draftContext
	}
	private var accountDescription: String
	{
		selectors.accountDescription
	}
	private var backendDescription: String
	{
		selectors.backendDescription
	}
	private var executionState: ExecutionState
	{
		selectors.executionState
	}
	private var models: [ModelOption]
	{
		selectors.models
	}
	private var modelListError: String?
	{
		selectors.modelListError
	}
	private var skillCatalog: SkillCatalog?
	{
		selectors.skillCatalog
	}
	private var skillError: String?
	{
		selectors.skillError
	}
	private var selectedModelID: String?
	{
		selectors.selectedModelID
	}
	private var selectedEffort: String?
	{
		selectors.selectedEffort
	}
	private var runPreferences: RunPreferences
	{
		selectors.runPreferences
	}
	private var hasStoredModelPreference: Bool
	{
		selectors.hasStoredModelPreference
	}
	private var showingArchived: Bool
	{
		selectors.showingArchived
	}
	private var managementRequestActive: Bool
	{
		selectors.managementRequestActive
	}
	private var loadingThreadID: String?
	{
		selectors.loadingThreadID
	}
	private var historyPageRequests: [String: HistoryLoadOperation]
	{
		selectors.historyPageRequests
	}
	private var pendingInteractions: [PendingInteraction]
	{
		selectors.pendingInteractions
	}
	private var activeTurnID: String?
	{
		selectors.activeTurnID
	}
	private var activePlan: TurnPlanUpdate?
	{
		selectors.activePlan
	}
	private var activeActivity: String?
	{
		selectors.activeActivity
	}
	private var activeTaskOutcomeMessage: String?
	{
		selectors.activeTaskOutcomeMessage
	}
	private var steerRequestActive: Bool
	{
		selectors.steerRequestActive
	}
	private var connectionGeneration: Int
	{
		selectors.connectionGeneration
	}
	private var needsReconciliation: Bool
	{
		selectors.needsReconciliation
	}
	private var hasUncertainRequest: Bool
	{
		selectors.hasUncertainRequest
	}
	private var isConnected: Bool
	{
		selectors.isConnected
	}
	private var commandLifetime: TaskCommandLifetime
	{
		selectors.commandLifetime
	}
	private var commandEventRevisions: [String: Int]
	{
		selectors.commandEventRevisions
	}
	private var project: URL?
	{
		selectors.project
	}
	private var taskWorkspace: TaskWorkspace?
	{
		selectors.taskWorkspace
	}
	private var workspaceCleanupInProgress: Bool
	{
		selectors.workspaceCleanupInProgress
	}
	private var isTaskActive: Bool
	{
		selectors.isTaskActive
	}
	private var canManageSelectedThread: Bool
	{
		selectors.canManageSelectedThread
	}
	private var viewedContent: ConversationProjection
	{
		selectors.viewedContent
	}
	private var selectedReview: ReviewTurn?
	{
		selectors.selectedReview
	}
	private var reviewedReferences: Set<ReviewReference>
	{
		selectors.reviewedReferences
	}
	private var reusableReferences: [ComposerContextItem]
	{
		selectors.reusableReferences
	}
	private var preferenceWarning: String?
	{
		selectors.preferenceWarning
	}

	func renameSelectedThread(_ name: String)
	{
		guard canManageSelectedThread, let selectedThreadID
		else
		{
			return
		}
		workspaceStore.dispatch(.conversations(.managementRequested(.rename(
			context: workspaceStore.operationContext(threadID: selectedThreadID),
			name: name.trimmingCharacters(in: .whitespacesAndNewlines)
		))))
	}

	func archiveSelectedThread()
	{
		guard canManageSelectedThread, let selectedThreadID
		else
		{
			return
		}
		let context = workspaceStore.operationContext(threadID: selectedThreadID)
		let managementOperation: ThreadManagementOperation = showingArchived
			? .unarchive(context) : .archive(context)
		workspaceStore.dispatch(.conversations(.managementRequested(managementOperation)))
	}

	func manageSidebarTask(
		_ id: String,
		permanentlyDelete: Bool
	)
	{
		let context = workspaceStore.operationContext(threadID: id)
		workspaceStore.dispatch(.conversations(.managementRequested(
			permanentlyDelete ? .delete(context) : .archive(context)
		)))
	}

	func selectReviewTurn(_ id: String)
	{
		workspaceStore.dispatch(.review(.turnSelected(
			workspaceStore.operationContext(threadID: selectedThreadID),
			conversation: workspaceStore.model.conversations.selectedConversation,
			turnID: id
		)))
	}

	func setReviewed(
		_ reviewed: Bool,
		reference: ReviewReference
	)
	{
		guard let selectedReview,
				selectedReview.threadID == reference.threadID,
				selectedReview.turnID == reference.turnID,
				let file = selectedReview.files.first(where:
				{
					$0.path == reference.path
				})
		else
		{
			return
		}
		let fingerprint: String
		if let hunkID = reference.hunkID
		{
			guard let hunk = file.hunks.first(where:
				{
					$0.id == hunkID
				})
			else
			{
				return
			}
			fingerprint = hunk.fingerprint
		}
		else
		{
			fingerprint = file.fingerprint
		}
		workspaceStore.dispatch(.review(.markerRequested(
			workspaceStore.operationContext(threadID: reference.threadID),
			identity: ReviewMarkerIdentity(
				reference: reference,
				fingerprint: fingerprint
			),
			reviewed: reviewed
		)))
	}

	func prepareChangeRequest(
		kind: ReviewRequestKind,
		reference: ReviewReference
	)
	{
		guard selectedThreadID == reference.threadID,
				let turn = viewedContent.reviewTurns.first(where:
				{
					$0.turnID == reference.turnID
				}),
				let file = turn.files.first(where:
				{
					$0.path == reference.path
				})
		else
		{
			return
		}
		let hunk = reference.hunkID.flatMap
		{
			hunkID in
			file.hunks.first
			{
				$0.id == hunkID
			}
		}
		let requestedHunkIsMissing = reference.hunkID != nil && hunk == nil
		if requestedHunkIsMissing
		{
			return
		}
		let key = workspaceStore.model.conversations.selectedConversation
		workspaceStore.dispatch(.review(.changeRequestPrepared(
			workspaceStore.operationContext(threadID: reference.threadID),
			ChangeRequest(
				reference: reference,
				file: file,
				hunk: hunk,
				kind: kind,
				sourceRevision: workspaceStore.model.review.conversations[key]?
					.sourceRevision ?? -1
			)
		)))
	}

	func updateProjectContext(_ context: ProjectContext)
	{
		workspaceStore.dispatch(.contextNavigation(.contextEdited(ContextSaveOperation(
			context: workspaceStore.operationContext(),
			revision: workspaceStore.model.contextNavigation.contextRevision + 1,
			value: context
		))))
	}

	func insertSavedPrompt(id: String)
	{
		workspaceStore.dispatch(.contextNavigation(.savedPromptInserted(
			workspaceStore.operationContext(threadID: selectedThreadID),
			promptID: id
		)))
	}

	func toggleBookmark(_ bookmark: ConversationBookmark)
	{
		workspaceStore.dispatch(.contextNavigation(.bookmarkToggled(
			workspaceStore.operationContext(),
			bookmark
		)))
	}

	func searchMessages(_ query: String)
	{
		workspaceStore.dispatch(.contextNavigation(.searchRequested(
			workspaceStore.operationContext(),
			query: query
		)))
	}

	func loadMoreSearchHistory()
	{
		workspaceStore.dispatch(.contextNavigation(.moreSearchHistoryRequested(
			workspaceStore.operationContext()
		)))
	}

	func dismissMessageSearch()
	{
		workspaceStore.dispatch(.contextNavigation(.searchDismissed(
			workspaceStore.operationContext()
		)))
	}

	func jumpToSearchHit(_ hit: MessageSearchHit)
	{
		requestJump(
			threadID: hit.threadID,
			turnID: hit.turnID,
			itemID: hit.itemID
		)
	}

	func jumpToNavigationTarget(_ target: ConversationJumpTarget)
	{
		requestJump(
			threadID: target.threadID,
			turnID: target.turnID,
			itemID: target.itemID
		)
	}

	func jumpToBookmark(_ bookmark: ConversationBookmark)
	{
		requestJump(
			threadID: bookmark.threadID,
			turnID: bookmark.turnID,
			itemID: bookmark.itemID
		)
	}

	func acknowledgeJump()
	{
		clearPendingJump()
	}

	private func clearPendingJump()
	{
		if let requestID = workspaceStore.model.contextNavigation.pendingJump?.context.requestID
		{
			workspaceStore.dispatch(.contextNavigation(.jumpAcknowledged(requestID: requestID)))
		}
	}

	private func requestJump(
		threadID: String,
		turnID: String,
		itemID: String?
	)
	{
		workspaceStore.dispatch(.contextNavigation(.jumpRequested(ConversationJumpOperation(
			context: workspaceStore.operationContext(threadID: threadID),
			turnID: turnID,
			itemID: itemID
		))))
	}

	func updateDraft(_ text: String)
	{
		let context = workspaceStore.operationContext(threadID: selectedThreadID)
		workspaceStore.dispatch(.composer(.draftEdited(
			context,
			conversation: workspaceStore.model.conversations.selectedConversation,
			text: text,
			revision: composerDraft.revision + 1
		)))
	}

	func addDraftContext(_ item: ComposerContextItem)
	{
		guard project != nil
		else
		{
			return
		}
		let context = workspaceStore.operationContext(threadID: selectedThreadID)
		workspaceStore.dispatch(.composer(.contextAttached(
			context,
			conversation: workspaceStore.model.conversations.selectedConversation,
			item: item,
			revision: composerDraft.revision + 1
		)))
	}

	func removeDraftContext(id: String)
	{
		guard project != nil
		else
		{
			return
		}
		let context = workspaceStore.operationContext(threadID: selectedThreadID)
		workspaceStore.dispatch(.composer(.contextRemoved(
			context,
			conversation: workspaceStore.model.conversations.selectedConversation,
			itemID: id,
			revision: composerDraft.revision + 1
		)))
	}

	func reuseReference(id: String)
	{
		guard let reference = reusableReferences.first(where:
			{
				$0.id == id
			})
		else
		{
			return
		}
		let context = workspaceStore.operationContext(threadID: selectedThreadID)
		workspaceStore.dispatch(.composer(.referenceReused(
			context,
			conversation: workspaceStore.model.conversations.selectedConversation,
			item: reference.reused(),
			revision: composerDraft.revision + 1
		)))
	}

	func selectModel(_ id: String?)
	{
		workspaceStore.dispatch(.preferences(.modelSelected(
			workspaceStore.operationContext(),
			id
		)))
	}

	func selectApprovalMode(_ mode: ApprovalMode)
	{
		workspaceStore.dispatch(.preferences(.approvalModeSelected(
			workspaceStore.operationContext(),
			mode
		)))
	}

	func setFastMode(_ enabled: Bool)
	{
		workspaceStore.dispatch(.preferences(.fastModeSelected(
			workspaceStore.operationContext(),
			enabled
		)))
	}

	func toggleProjectPin(_ project: URL)
	{
		store.dispatch(.workspaceLifecycle(.projectPinRequested(
			store.operationContext(),
			project
		)))
	}

	func renameProject(
		_ project: URL,
		name: String
	)
	{
		store.dispatch(.workspaceLifecycle(.projectRenameRequested(
			store.operationContext(),
			project,
			name: name
		)))
	}

	func selectEffort(_ effort: String?)
	{
		workspaceStore.dispatch(.preferences(.effortSelected(
			workspaceStore.operationContext(),
			effort
		)))
	}

	func signIn()
	{
		workspaceStore.dispatch(.preferences(.signInRequested(workspaceStore.operationContext())))
	}

	/// Returns the submission operation, including acknowledgement and retained-context cleanup.
	@discardableResult
	func send() -> WorkspaceOperationHandle?
	{
		let collaborationMode: CollaborationMode?
		switch prepareComposerCommandInput(
			draft,
			steering: false
		)
		{
		case .handled(let operation): return operation
		case .message(
			_,
			let mode
		): collaborationMode = mode
		}
		guard WorkspaceEligibility(model: store.model).canSend
		else
		{
			return nil
		}
		let submittedDraft = draft
		guard let draftText = ComposerPromptText.submittedText(
			submittedDraft,
			collaborationMode: collaborationMode
		)
		else
		{
			return nil
		}
		let submittedContext = draftContext
		guard !draftText.isEmpty || !submittedContext.isEmpty
		else
		{
			return nil
		}
		let submission = captureSubmission(
			draftText: draftText,
			collaborationMode: collaborationMode
		)
		workspaceStore
			.dispatch(.workspaceLifecycle(.inputPreparationRequested(.submission(submission))))
		return workspaceStore.operation(for: submission.context)
	}

	private func captureSubmission(
		draftText: String,
		collaborationMode: CollaborationMode?
	) -> ComposerSubmission
	{
		let requestText = ProjectProductivity.requestText(
			context: projectContext,
			draft: draftText
		)
		let inputs: [TurnInput] = [.text(requestText)]
		let selectedSkills = ProjectProductivity.resolvedSkill(
			context: projectContext,
			in: skillCatalog
		).map
		{
			[$0]
		} ?? []
		let modelID = selectedModelID
		let effort = selectedEffort
		let submittedRunPreferences = runPreferences
		let originatingThreadID = selectedThreadID
		let context = workspaceStore.operationContext(threadID: originatingThreadID)
		return ComposerSubmission(
			context: context,
			conversation: originatingThreadID
				.map(ConversationKey.thread) ?? .newChat,
			draft: composerDraft,
			inputs: inputs,
			skills: selectedSkills,
			modelID: modelID,
			effort: effort,
			preferences: submittedRunPreferences,
			retainedContextRequestID: UUID(),
			projectContextRevision: store.model.contextNavigation.contextRevision,
			collaborationMode: collaborationMode,
			serviceTier: submittedRunPreferences.fastMode
				? FastModeAvailability.serviceTier(in: store.model) : "default"
		)
	}

	@discardableResult
	func stop() -> WorkspaceOperationHandle?
	{
		requestStop(for: store.model.execution)
	}

	@discardableResult
	func stop(
		conversation: ConversationKey,
		capturedOwner: ExecutionOwner?
	) -> WorkspaceOperationHandle?
	{
		let execution: ExecutionModel
		if let capturedOwner
		{
			guard let capturedExecution = store.model.execution(for: capturedOwner.submission),
					capturedExecution.owner == capturedOwner
			else
			{
				return nil
			}
			execution = capturedExecution
		}
		else
		{
			execution = store.model.execution(for: conversation)
			guard execution.owner == nil
			else
			{
				return nil
			}
		}
		return requestStop(for: execution)
	}

	func stopAll()
	{
		let executions = store.model.allExecutions.filter
		{
			$0.isTaskActive || $0.needsReconciliation
		}
		for execution in executions
		{
			requestStop(for: execution)
		}
	}

	@discardableResult
	private func requestStop(for execution: ExecutionModel) -> WorkspaceOperationHandle?
	{
		var context = workspaceStore.operationContext(threadID: execution.activeThreadID)
		context.turnID = execution.activeTurnID
		workspaceStore.dispatch(.execution(.stopRequested(
			context,
			ownerRequestID: execution.owner?.submission.requestID
		)))
		return store.operation(for: context)
	}

	func steer(_ text: String)
	{
		let submittedPrompt: String
		switch prepareComposerCommandInput(
			text,
			steering: true
		)
		{
		case .handled: return
		case .message(
			let message,
			_
		): submittedPrompt = message
		}
		guard WorkspaceEligibility(model: store.model).canSteer,
				let activeThreadID, let activeTurnID
		else
		{
			return
		}
		let instruction = submittedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
		let submittedContext = draftContext
		guard !instruction.isEmpty || !submittedContext.isEmpty
		else
		{
			return
		}
		let requestText = ProjectProductivity.requestText(
			context: projectContext,
			draft: instruction
		)
		let inputs: [TurnInput] = [.text(requestText)]
		var context = workspaceStore.operationContext(threadID: activeThreadID)
		context.turnID = activeTurnID
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread(activeThreadID),
			draft: ComposerDraft(
				text: text,
				context: submittedContext,
				revision: composerDraft.revision,
				lifetime: composerDraft.lifetime
			),
			inputs: inputs,
			skills: [],
			modelID: selectedModelID,
			effort: selectedEffort,
			preferences: runPreferences,
			retainedContextRequestID: UUID(),
			projectContextRevision: store.model.contextNavigation.contextRevision
		)
		workspaceStore
			.dispatch(.workspaceLifecycle(.inputPreparationRequested(.steering(SteeringOperation(
				context: context,
				submission: submission
			)))))
	}

	@discardableResult
	func respond(
		to interaction: PendingInteraction,
		with response: InteractionResponse
	) -> WorkspaceOperationHandle?
	{
		var context = workspaceStore.operationContext(threadID: interaction.threadId)
		context.turnID = interaction.turnId
		workspaceStore
			.dispatch(.execution(.interactionResponseRequested(InteractionResponseOperation(
				context: context,
				interactionID: interaction.id,
				response: response
			))))
		return store.operation(for: context)
	}

	private func report(_ reason: String)
	{
		store.dispatch(.workspaceLifecycle(.capabilityRejected(
			store.operationContext(),
			reason: reason
		)))
	}

	func start()
	{
		store.dispatch(.workspaceLifecycle(.bootstrapRequested(store.operationContext())))
	}

	func connect() async
	{
		let initial = store.operationContext()
		store.dispatch(.workspaceLifecycle(.bootstrapRequested(initial)))
		let accepted = OperationContext(
			workspace: store.model.identity,
			generation: store.model.connection.generation,
			requestID: initial.requestID
		)
		_ = await store.operation(for: accepted)?.wait()
	}

	func openProject(_ url: URL)
	{
		guard taskWorkspace == nil
		else
		{
			report("Select the source checkout before opening another project.")
			return
		}
		guard !isTaskActive, !managementRequestActive, !workspaceCleanupInProgress
		else
		{
			report("Finish or stop the current task before changing projects.")
			return
		}
		let canonical = url.standardizedFileURL
		store.dispatch(.workspaceLifecycle(.projectOpeningRequested(
			store.operationContext(),
			canonical
		)))
	}

	func newChat()
	{
		store.dispatch(.conversations(.newChatOpened(store.operationContext())))
	}

	@discardableResult
	func selectThread(_ id: String) -> WorkspaceOperationHandle?
	{
		let context = store.operationContext(threadID: id)
		store.dispatch(.conversations(.selectionRequested(context)))
		return store.operation(for: context)
	}

	func refreshThreads()
	{
		store.dispatch(.workspaceLifecycle(.refreshRequested(store.operationContext())))
	}

	func setArchivedFilter(_ archived: Bool)
	{
		guard project != nil, archived != showingArchived
		else
		{
			return
		}
		store.dispatch(.workspaceLifecycle(.archivedSelectionRequested(
			store.operationContext(),
			archived: archived
		)))
	}

	func updateConversationViewport(_ viewport: ConversationViewport)
	{
		guard let threadID = selectedThreadID
		else
		{
			return
		}
		store.dispatch(.conversations(.viewportChanged(
			store.operationContext(threadID: threadID),
			viewport,
			observedAt: store.now()
		)))
	}

	func loadTurnPreview(_ turnID: String)
	{
		guard let threadID = selectedThreadID
		else
		{
			return
		}
		store.dispatch(.conversations(.previewAccessed(
			store.operationContext(threadID: threadID),
			turnID,
			observedAt: store.now()
		)))
		if viewedContent.loadedTurns.contains(where:
			{
				$0.id == turnID
			})
		{
			return
		}
		guard let index = store.model.conversations.turnReferenceIndices[threadID],
				index.previews[turnID] == nil,
				index.pendingPreviewRead?.reference.id != turnID,
				index.pendingPreviewPromotion?.producer.reference.id != turnID,
				let reference = index.references.first(where:
				{
					$0.id == turnID
				})
		else
		{
			return
		}
		store.dispatch(.conversations(.turnContentsRequested(ConversationTurnReadOperation(
			context: store.operationContext(threadID: threadID),
			reference: reference,
			commandRevision: commandEventRevisions[threadID, default: 0],
			isPreview: true
		))))
	}

	func loadEarlierTurnReferences()
	{
		guard let threadID = selectedThreadID
		else
		{
			return
		}
		let index = store.model.conversations.turnReferenceIndices[threadID]
		guard index?.pendingRead == nil, index?.hasLoadedPage != true || index?.nextCursor != nil
		else
		{
			return
		}
		requestTurnReferences(
			context: store.operationContext(threadID: threadID),
			cursor: index?.nextCursor
		)
	}

	func loadEarlierTurns()
	{
		if let threadID = selectedThreadID,
			let viewport = store.model.conversations.turnReferenceIndices[threadID]?.viewport,
			viewport.anchorTurnID != nil
		{
			updateConversationViewport(viewport)
			return
		}
		guard let threadID = selectedThreadID, let cursor = viewedContent.nextTurnsCursor,
				let path = store.model.identity.canonicalCheckoutPath,
				historyPageRequests[threadID] == nil
		else
		{
			return
		}
		store.dispatch(.conversations(.earlierTurnsRequested(HistoryLoadOperation(
			context: store.operationContext(threadID: threadID),
			pageScope: HistoryPageScope(
				projectPath: path,
				generation: connectionGeneration,
				cursor: cursor
			),
			commandRevision: commandEventRevisions[threadID, default: 0]
		))))
	}
}
