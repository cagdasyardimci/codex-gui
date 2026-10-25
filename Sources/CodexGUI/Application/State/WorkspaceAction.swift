import Foundation

/// The boundary routes semantic feature actions; it never carries mutation closures.
enum WorkspaceAction
{
	case workspaceLifecycle(WorkspaceLifecycleAction)
	case connection(ConnectionAction)
	case execution(ExecutionAction)
	case composer(ComposerAction)
	case composerCommand(ComposerCommandAction)
	case conversations(ConversationsAction)
	case review(ReviewAction)
	case contextNavigation(ContextNavigationAction)
	case preferences(PreferencesAction)
	case usage(UsageAction)
}

enum ConnectionAction
{
	case connectRequested(OperationContext)
	case projectOpened(
		WorkspaceIdentity,
		selectedThreadID: String?
	)
	case projectRestored(
		OperationContext,
		pendingCommands: [TaskCommandOwnership],
		selectedThreadID: String?,
		pendingExecutions: [String] = []
	)
	case shutdownRequested
	case executableVersionReceived(
		OperationContext,
		OperationResult<String>
	)
	case connectionFinished(
		OperationContext,
		OperationResult<Void>
	)
	case disconnected(
		workspace: WorkspaceIdentity,
		generation: Int,
		message: String
	)
}

enum ExecutionAction
{
	case submissionRequested(ComposerSubmission)
	case conversationSelected(
		threadID: String?,
		recovering: Bool
	)
	case conversationCleared
	case recoveryTargetUnavailable
	case preparedConversationAdopted(PreparedConversationWrite)
	case preparedPersistenceFinished(
		OperationContext,
		OperationResult<PreparedSubmission>
	)
	case draftAcknowledgementFinished(
		OperationContext,
		OperationResult<SubmissionDraftAcknowledgement>
	)
	case backendObserved(
		OperationContext,
		AppServerEvent,
		observedAt: Date? = nil
	)
	case completedHistoryRequested(ReconciliationOperation)
	case completedHistoryReceived(
		ReconciliationOperation,
		OperationResult<ThreadDetail>
	)
	case historyObserved(
		ReconciliationOperation,
		ThreadDetail
	)
	case stopRequested(
		OperationContext,
		ownerRequestID: UUID? = nil
	)
	case steeringRequested(SteeringOperation)
	case steeringTransportFinished(
		SteeringOperation,
		OperationResult<String>
	)
	case interactionResponseRequested(InteractionResponseOperation)
	case reconciliationRequested(ReconciliationOperation)
	case submissionPrepared(
		OperationContext,
		OperationResult<PreparedSubmission>
	)
	case submissionAcknowledged(
		OperationContext,
		SubmissionAcknowledgement
	)
	case submissionCancelledBeforeSend(OperationContext)
	case submissionStartFailed(
		OperationContext,
		OperationFailure,
		PendingGitTurnBaselineCapture?
	)
	case gitTurnBaselineBindingFinished(
		OperationContext,
		threadID: String,
		turnID: String,
		GitTurnBaselineResult
	)
	case gitTurnBaselineDiscarded(
		OperationContext,
		UUID
	)
	case submissionFailed(
		OperationContext,
		OperationFailure
	)
	case steeringFinished(
		OperationContext,
		OperationResult<String>
	)
	case interruptionFinished(
		OperationContext,
		OperationResult<Void>
	)
	case interactionResponseFinished(
		OperationContext,
		OperationResult<Void>
	)
	case reconciliationFinished(
		OperationContext,
		OperationResult<ThreadDetail>
	)
	case turnStarted(
		OperationContext,
		CodexTurn
	)
	case turnFinished(
		OperationContext,
		AgentTurnOutcome
	)
	case commandObserved(
		OperationContext,
		CodexItem
	)
	case interactionReceived(
		OperationContext,
		PendingInteraction
	)
	case interactionResolved(
		OperationContext,
		interactionID: String
	)
	case planReceived(
		OperationContext,
		TurnPlanUpdate
	)
	case activityReceived(
		OperationContext,
		String
	)
	case backendErrorReceived(
		OperationContext,
		OperationFailure
	)
}

/// A composed acknowledgement binds backend ownership and conditionally clears the captured draft.
struct SubmissionAcknowledgement
{
	let thread: ThreadSummary
	let turn: CodexTurn
	var gitTurnBaseline: GitTurnBaselineReference? = nil
	var gitTurnBaselineResult: GitTurnBaselineResult? = nil
}

enum ComposerAction
{
	case submissionReleaseFinished(
		WorkspaceSubmissionReleaseOperation,
		OperationResult<SubmissionReservationRelease>
	)
	case conversationRestored(
		OperationContext,
		conversation: ConversationKey,
		draft: ComposerDraft,
		references: [ComposerContextItem]
	)
	case draftEdited(
		OperationContext,
		conversation: ConversationKey,
		text: String,
		revision: Int
	)
	case contextAttached(
		OperationContext,
		conversation: ConversationKey,
		item: ComposerContextItem,
		revision: Int
	)
	case contextRemoved(
		OperationContext,
		conversation: ConversationKey,
		itemID: String,
		revision: Int
	)
	case referenceReused(
		OperationContext,
		conversation: ConversationKey,
		item: ComposerContextItem,
		revision: Int
	)
	case draftRestored(
		OperationContext,
		conversation: ConversationKey,
		draft: ComposerDraft
	)
	case referencesLoaded(
		OperationContext,
		conversation: ConversationKey,
		[ComposerContextItem]
	)
	case draftPersistenceFinished(
		OperationContext,
		OperationResult<Void>
	)
}

enum ConversationsAction
{
	case projectArchiveRequested(ProjectArchiveOperation)
	case projectArchiveFinished(
		ProjectArchiveOperation,
		ProjectArchiveResult
	)
	case newChatRequested
	case newChatOpened(OperationContext)
	case historyRequested(ConversationReadOperation)
	case historyReceived(
		ConversationReadOperation,
		OperationResult<ThreadDetail>
	)
	case selectionPersistenceFinished(
		OperationContext,
		OperationResult<Void>
	)
	case selectionRequested(OperationContext)
	case lockedChatRetryRequested(OperationContext)
	case archivedFilterRequested(
		OperationContext,
		archived: Bool
	)
	case threadListRequested(ConversationListOperation)
	case earlierTurnsRequested(HistoryLoadOperation)
	case turnReferencesRequested(TurnReferenceReadOperation)
	case turnContentsRequested(ConversationTurnReadOperation)
	case previewExpiryRequested(OperationContext)
	case cacheExpired(
		OperationContext,
		observedAt: Date = .distantPast
	)
	case previewAccessed(
		OperationContext,
		String,
		observedAt: Date = .distantPast
	)
	case viewportChanged(
		OperationContext,
		ConversationViewport,
		observedAt: Date = .distantPast
	)
	case turnReferencesReceived(
		TurnReferenceReadOperation,
		OperationResult<TurnReferencePage>
	)
	case turnContentsReceived(
		ConversationTurnReadOperation,
		OperationResult<CodexTurn>,
		observedAt: Date = .distantPast,
		preview: ConversationTurnPreview? = nil
	)
	case managementRequested(ThreadManagementOperation)
	case threadListReceived(
		ConversationListOperation,
		OperationResult<[ThreadSummary]>
	)
	case selectionReceived(
		OperationContext,
		OperationResult<ThreadDetail>
	)
	case earlierTurnsReceived(
		HistoryLoadOperation,
		OperationResult<HistoryPage>
	)
	case managementFinished(
		OperationContext,
		OperationResult<Void>
	)
	case itemStarted(
		OperationContext,
		CodexItem
	)
	case itemFinished(
		OperationContext,
		CodexItem
	)
	case agentMessageDelta(
		OperationContext,
		String
	)
	case commandOutputDelta(
		OperationContext,
		String
	)
	case fileChangesReceived(
		OperationContext,
		[FileChange]
	)
	case aggregateDiffReceived(
		OperationContext,
		String
	)
}

struct HistoryPage
{
	let turns: [CodexTurn]
	let nextCursor: String?
}

enum ReviewAction
{
	case turnSelected(
		OperationContext,
		conversation: ConversationKey,
		turnID: String
	)
	case markerRequested(
		OperationContext,
		identity: ReviewMarkerIdentity,
		reviewed: Bool
	)
	case changeRequestPrepared(
		OperationContext,
		ChangeRequest
	)
	case markersReceived(
		ReviewMarkerReadOperation,
		OperationResult<[ReviewMarkerIdentity]>
	)
	case markerPersistenceFinished(
		ReviewMarkerWriteOperation,
		OperationResult<Void>
	)
}

/// Retains the source's fingerprint/provenance when requesting a targeted revision.
struct ChangeRequest
{
	let reference: ReviewReference
	let file: ReviewFile
	let hunk: ReviewHunk?
	let kind: ReviewRequestKind
	let sourceRevision: Int
}

enum ContextNavigationAction
{
	case contextLoadRequested(ContextLoadOperation)
	case contextEdited(ContextSaveOperation)
	case savedPromptInserted(
		OperationContext,
		promptID: String
	)
	case bookmarkToggled(
		OperationContext,
		ConversationBookmark
	)
	case searchRequested(
		OperationContext,
		query: String
	)
	case moreSearchHistoryRequested(OperationContext)
	case searchDismissed(OperationContext)
	case messageSearchFinished(
		MessageSearchOperation,
		OperationResult<MessageSearchResults>
	)
	case jumpRequested(ConversationJumpOperation)
	case jumpAcknowledged(requestID: UUID)
	case skillsRefreshRequested(SkillsRefreshOperation)
	case skillsInvalidated(OperationContext)
	case contextReceived(
		ContextLoadOperation,
		OperationResult<ProjectContext>
	)
	case contextPersistenceFinished(
		ContextSaveOperation,
		OperationResult<Void>
	)
	case skillsReceived(
		SkillsRefreshOperation,
		OperationResult<SkillCatalog>
	)
}

enum PreferencesAction
{
	case projectRemoved(
		OperationContext,
		canonicalPath: String
	)
	case modelSelected(
		OperationContext,
		String?
	)
	case effortSelected(
		OperationContext,
		String?
	)
	case approvalModeSelected(
		OperationContext,
		ApprovalMode
	)
	case fastModeSelected(
		OperationContext,
		Bool
	)
	case taskPinToggled(
		OperationContext,
		ThreadSummary
	)
	case projectPinToggled(
		OperationContext,
		canonicalPath: String
	)
	case projectRenamed(
		OperationContext,
		canonicalPath: String,
		name: String
	)
	case projectRemembered(
		OperationContext,
		canonicalPath: String
	)
	case signInRequested(OperationContext)
	case accountRefreshRequested(OperationContext)
	case modelsRefreshRequested(OperationContext)
	case restored(PreferencesRestoration)
	case modelsReceived(
		OperationContext,
		OperationResult<[ModelOption]>
	)
	case accountReceived(
		OperationContext,
		OperationResult<AccountStatus>
	)
	case signInURLReceived(
		OperationContext,
		OperationResult<URL>
	)
	case persistenceFinished(
		OperationContext,
		OperationResult<Void>
	)
}

struct PreferencesRestoration
{
	let modelPreference: ProjectModelPreference?
	let runPreferences: RunPreferences
	let recentProjects: [URL]
	let pinnedProjectPaths: Set<String>
	let projectDisplayNames: [String: String]
	var pinnedTasks: [ThreadSummary] = []
	var removedProjectPaths: Set<String> = []
}

enum UsageAction
{
	case refreshRequested(OperationContext)
	case invalidated(
		workspace: WorkspaceIdentity,
		generation: Int
	)
	case limitsReceived(
		UsageReadOperation,
		OperationResult<UsageObservation>
	)
	case freshnessDeadlineElapsed(
		UsageDeadlineOperation,
		now: Date
	)
}

struct UsageObservation
{
	let snapshot: AccountRateLimitsSnapshot
	let fetchedAt: Date
	let freshnessDeadline: Date
}

enum WorkspaceLifecycleAction
{
	case sourceStartupRequested(OperationContext)
	case sourceStartupRestored(
		OperationContext,
		OperationResult<WorkspaceSourceStartup>
	)
	case managedRecordRecoveryConflicted(
		WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		cleanup: WorkspaceCleanupRequest?,
		message: String
	)
	case managedRecordRecovered(
		WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		recovered: TaskWorkspace
	)
	case cleanupReserved(WorkspaceCleanupRequest)
	case cleanupReleased(WorkspaceCleanupRequest)
	case quitFrozen(
		WorkspaceQuitRequest,
		WorkspaceLifecycleOwnerReference
	)
	case quitThawed(
		WorkspaceQuitRequest,
		WorkspaceLifecycleOwnerReference
	)
	case inputPreparationRequested(ComposerInputPreparationOperation)
	case inputPreparationFinished(
		ComposerInputPreparationOperation,
		OperationResult<[TurnInput]>
	)
	case unsentSubmissionReleased(OperationContext)
	case projectPinRequested(
		OperationContext,
		URL
	)
	case projectRenameRequested(
		OperationContext,
		URL,
		name: String
	)
	case projectOpeningRequested(
		OperationContext,
		URL,
		selectedThreadID: String? = nil
	)
	case projectOpeningFinished(
		OperationContext,
		OperationResult<WorkspaceProjectOpening>
	)
	case archivedSelectionRequested(
		OperationContext,
		archived: Bool
	)
	case archivedSelectionRestored(
		OperationContext,
		archived: Bool,
		threadID: String?
	)
	case initialHydrationRequested(OperationContext)
	case bootstrapRequested(OperationContext)
	case refreshRequested(OperationContext)
	case composerHydrationRequested(OperationContext)
	case capabilityRejected(
		OperationContext,
		reason: String
	)
	case diagnosticsReceived(
		OperationContext,
		BackendDiagnosticsSnapshot
	)
	case reusableReferencesReceived(
		ReusableReferenceValidationOperation,
		[ComposerContextItem]
	)
	case shutdownRequested
}

struct ReusableReferenceValidationOperation
{
	let context: OperationContext
	let conversation: ConversationKey
	let revision: Int
	let items: [ComposerContextItem]
}

enum ComposerInputPreparationOperation
{
	case submission(ComposerSubmission)
	case steering(SteeringOperation)
	var submission: ComposerSubmission
	{
		switch self
		{
		case .submission(let submission): return submission
		case .steering(let operation): return operation.submission
		}
	}
	var context: OperationContext
	{
		switch self
		{
		case .submission(let submission): return submission.context
		case .steering(let operation): return operation.context
		}
	}
}

struct WorkspaceProjectOpening
{
	let identity: WorkspaceIdentity
	let selectedThreadID: String?
}

/// Startup captures only durable values; managed owners never use this source selection.
struct WorkspaceSourceStartup
{
	let project: WorkspaceProjectOpening?
	let pendingCommands: [TaskCommandOwnership]
	var pendingExecutions: [String] = []
	let preferences: PreferencesRestoration
}
