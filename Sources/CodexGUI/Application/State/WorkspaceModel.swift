import Foundation

/// Connection, execution, and composer are canonical reducer-owned values.
/// Canonical feature values are reduced together before observers are notified.
struct WorkspaceModel
{
	var identity: WorkspaceIdentity
	var lifecycle = WorkspaceLifecycleModel()
	var connection = ConnectionModel()
	var executions = ExecutionRegistry()
	private var executionReductionIdentity: ExecutionConversationIdentity?
	/// Publications project the displayed conversation; reductions use captured ownership.
	var execution: ExecutionModel
	{
		get
		{
			let identity = executionReductionIdentity.map(executions.canonicalIdentity)
				?? selectedExecutionIdentity
			return executions.entries[identity] ?? emptyExecution
		}
		set
		{
			let identity = executionReductionIdentity.map(executions.canonicalIdentity)
				?? selectedExecutionIdentity
			executions.entries[identity] = newValue
		}
	}
	var composer = ComposerModel()
	var composerCommands = ComposerCommandModel()
	var conversations = ConversationsModel()
	var review = ReviewModel()
	var contextNavigation = ContextNavigationModel()
	var preferences = PreferencesModel()
	var usage = UsageModel()

	init(identity: WorkspaceIdentity)
	{
		self.identity = identity
	}

	var selectedExecutionIdentity: ExecutionConversationIdentity
	{
		executionIdentity(for: conversations.selectedConversation)
	}

	func executionIdentity(for conversation: ConversationKey) -> ExecutionConversationIdentity
	{
		switch conversation
		{
		case .thread(let id): return .thread(id)
		case .newChat:
			return .newChat(lifetime: max(
				composer.drafts[.newChat]?.lifetime ?? 0,
				composer.pendingNewChatLifetime ?? 0
			))
		}
	}

	private var emptyExecution: ExecutionModel
	{
		var value = ExecutionModel()
		value.state = connection.isConnected ? .ready : .disconnected
		return value
	}

	@MainActor
	mutating func reduceExecutionScope(
		_ identity: ExecutionConversationIdentity?,
		body: @MainActor (inout WorkspaceModel) -> WorkspaceReduction
	) -> WorkspaceReduction
	{
		let previous = executionReductionIdentity
		if let identity
		{
			executionReductionIdentity = executions.canonicalIdentity(identity)
		}
		defer
		{
			executionReductionIdentity = previous.map(executions.canonicalIdentity)
		}
		return body(&self)
	}

	mutating func adoptExecution(
		for context: OperationContext,
		threadID: String
	) -> Bool
	{
		guard let source = executions.identity(for: context)
		else
		{
			return false
		}
		let destination = ExecutionConversationIdentity.thread(threadID)
		guard executions.adopt(
			source,
			as: destination
		)
		else
		{
			return false
		}
		if executionReductionIdentity.map(executions.canonicalIdentity) == destination
		{
			executionReductionIdentity = destination
		}
		return true
	}

	func execution(for conversation: ConversationKey) -> ExecutionModel
	{
		executions.entries[executionIdentity(for: conversation)] ?? emptyExecution
	}

	func execution(for context: OperationContext) -> ExecutionModel?
	{
		guard context.belongsTo(
			workspace: identity,
			generation: connection.generation
		)
		else
		{
			return nil
		}
		if let owner = executions.identity(for: context)
		{
			return executions.entries[owner]
		}
		return context.threadID.flatMap
		{
			executions.entries[.thread($0)]
		}
	}

	var allExecutions: [ExecutionModel]
	{
		executions.entries.keys.sorted
		{
			$0.isOrdered(before: $1)
		}.compactMap
		{
			executions.entries[$0]
		}
	}

	var hasActiveExecution: Bool
	{
		allExecutions.contains(where: \.isTaskActive)
	}

	var blocksExecutionCleanup: Bool
	{
		allExecutions.contains(where: \.blocksCleanup)
	}

	var hasExecutionReconciliation: Bool
	{
		allExecutions.contains(where: \.needsReconciliation)
	}

	var hasUncertainExecutionRequest: Bool
	{
		allExecutions.contains(where: \.hasUncertainRequest)
	}

	var pendingCommandOwnership: [TaskCommandOwnership]
	{
		allExecutions.flatMap
		{
			Array($0.commandLifetime.pending)
		}.sorted
		{
			if $0.threadID != $1.threadID
			{
				return $0.threadID < $1.threadID
			}
			if $0.turnID != $1.turnID
			{
				return $0.turnID < $1.turnID
			}
			return $0.itemID < $1.itemID
		}
	}

	var executionRecoveryThreadIDs: [String]
	{
		var threadIDs = Set(pendingCommandOwnership.map(\.threadID))
		for execution in allExecutions where execution.blocksCleanup
		{
			if let threadID = execution.activeThreadID ?? execution.owner?.submission.threadID
			{
				threadIDs.insert(threadID)
			}
		}
		return threadIDs.sorted()
	}

	mutating func updateAllExecutions(_ update: (inout ExecutionModel) -> Void)
	{
		if executions.entries[selectedExecutionIdentity] == nil
		{
			executions.entries[selectedExecutionIdentity] = emptyExecution
		}
		for identity in executions.entries.keys.sorted(by:
			{
				$0.isOrdered(before: $1)
			})
		{
			update(&executions.entries[identity]!)
		}
	}
}

struct ConnectionModel
{
	var generation = 0
	var isConnected = false
	var pendingConnection: OperationContext?
	var backendDescription = "Locating Codex…"
	var statusMessage: String?
}

enum AgentTurnOutcome: Equatable
{
	case completed
	case stopped
	case failed(String)
}

struct ExecutionOwner: Equatable
{
	/// Remains valid when thread/turn IDs are absent or assigned later.
	var submission: OperationContext
}

struct ExecutionModel
{
	var gitTurnBaselineRevisions: [String: Int] = [:]
	var gitTurnBaselineBindings: [String: GitTurnBaselineBindingStatus] = [:]
	var pendingGitTurnBaselineCapture: PendingGitTurnBaselineCapture?
	var owner: ExecutionOwner?
	var activeThreadID: String?
	var activeTurnID: String?
	var statusMessage: String?
	var deferredTurnOutcome: ExecutionState?
	var deferredTurnMessage: String?
	var submissionRequest: OperationContext?
	var state: ExecutionState = .disconnected
	var agentOutcome: AgentTurnOutcome?
	var commandLifetime = TaskCommandLifetime()
	var commandEventRevisions: [String: Int] = [:]
	var pendingInteractions: [PendingInteraction] = []
	/// A possibly sent response remains reserved until server resolution or disconnection.
	var pendingResponses: [String: InteractionResponseOperation] = [:]
	var pendingSteering: OperationContext?
	var pendingInterruption: InterruptionOperation?
	var lastReconciledRequestID: UUID?
	var pendingReconciliation: ReconciliationOperation?
	var activePlan: TurnPlanUpdate?
	var activeActivity: String?
	var outcomeMessage: String?

	/// Stop intent and interrupt transport acknowledgement are independent facts.
	var stopRequested = false
	var stopContext: OperationContext?
	var interruptRequestSent = false
	/// A disconnected transport does not establish the outcome of a remote request.
	var needsReconciliation = false
	var hasUncertainRequest = false
	var reconcilingCommandOutcome = false

	/// Terminal agent evidence never clears the independent command barrier.
	var isTaskActive: Bool
	{
		state.isBusy || commandLifetime.hasPendingCommands || hasUncertainRequest
			|| (needsReconciliation && activeThreadID != nil)
	}

	var blocksCleanup: Bool
	{
		isTaskActive || needsReconciliation
	}
}

enum ConversationKey: Hashable
{
	case newChat
	case thread(String)

	var threadID: String?
	{
		switch self
		{
		case .newChat: return nil
		case .thread(let id): return id
		}
	}
}

struct ComposerDraft: Equatable
{
	var text = ""
	var context: [ComposerContextItem] = []
	/// Supplied by draft actions, so acknowledging an earlier edit cannot clear a later edit.
	var revision = 0
	/// Distinguishes explicit New Chat interactions and later draft adoption.
	var lifetime = 0
}

struct ComposerSubmission
{
	let context: OperationContext
	let conversation: ConversationKey
	let draft: ComposerDraft
	let inputs: [TurnInput]
	let skills: [SkillReference]
	let modelID: String?
	let effort: String?
	let preferences: RunPreferences
	let retainedContextRequestID: UUID
	var projectContextRevision: Int? = nil
	var collaborationMode: CollaborationMode? = nil
	var serviceTier: String? = nil
}

enum ComposerPersistenceKey: Equatable
{
	case draft(ConversationKey)
	case submission(UUID)
}

struct ComposerPersistenceFailure
{
	let context: OperationContext
	let key: ComposerPersistenceKey
	let message: String
}

struct ComposerModel
{
	var workspace: WorkspaceIdentity?
	var preparedSubmissions: [UUID: PreparedSubmission] = [:]
	var submissionConversations: [UUID: ConversationKey] = [:]
	var uncertainSubmissions: Set<UUID> = []
	var resolvingSubmissions: [UUID: OperationContext] = [:]
	var acknowledgedSubmissions: Set<UUID> = []
	var persistenceFailure: ComposerPersistenceFailure?
	var persistenceError: String?
	{
		persistenceFailure?.message
	}
	var pendingDraftWrites: [ConversationKey: UUID] = [:]
	/// Accepted New Chat identity awaiting the first stored draft hydration.
	var pendingNewChatLifetime: Int?

	var drafts: [ConversationKey: ComposerDraft] = [:]
	var sentReferences: [ConversationKey: [ComposerContextItem]] = [:]
	var pendingSubmissions: [UUID: ComposerSubmission] = [:]
	/// Exact empty draft produced at acceptance; later edits must survive completion or failure.
	var clearedSubmissionDrafts: [UUID: ComposerDraft] = [:]
}

/// Value content replaces the legacy reference container when conversation ownership moves.
/// Canonical turns and provisional streaming entries are distinct observations, not two writers.
struct ConversationContentModel
{
	var loadedTurns: [CodexTurn] = []
	{
		didSet
		{
			loadedUserReferences = ConversationHistoryReferences.collect(from: loadedTurns)
			loadedHistoryRevision += 1
			turnPayloadCosts = nil
		}
	}
	/// Canonical references are stable while provisional entries stream.
	/// Memberwise initialization bypasses observers, so selectors can derive an uncached value.
	private(set) var loadedUserReferences: [UserMessageReference]?
	/// Searchable history changes independently of provisional streaming entries.
	private(set) var loadedHistoryRevision = 0
	private(set) var turnPayloadCosts: ConversationTurnPayloadCosts?
	/// The latest actual source turn observed independently of local execution ownership.
	var latestObservedGitTurnID: String?
	/// Editing identity survives transcript payload eviction.
	var latestReportedGitTurn: ConversationReportedGitTurn?
	var hasResolvedReportedGitTurn = false
	var turnTimings: [String: ConversationTurnTiming] = [:]
	var hasLoadedHistory = false
	{
		didSet
		{
			if hasLoadedHistory != oldValue
			{
				loadedHistoryRevision += 1
			}
		}
	}
	var nextTurnsCursor: String?
	{
		didSet
		{
			if nextTurnsCursor != oldValue
			{
				loadedHistoryRevision += 1
			}
		}
	}
	/// Local user rows are matched only to the turn that accepted them.
	var localUserMessageTurnIDs: [String: String] = [:]
	var entries: [ConversationEntry] = []
	{
		didSet
		{
			entryIndices = nil
			formattedCommandEntries = []
			entryPayloadRevision += 1
			entryPayloadCosts = nil
		}
	}
	/// Direct replacement and memberwise initialization rebuild the first-match lookup lazily.
	private(set) var entryIndices: [String: Int]?
	private(set) var entryPayloadRevision = 0
	private(set) var entryPayloadCosts: ConversationEntryPayloadCosts?
	/// Indexed mutations retain formatting knowledge; other writes must canonicalize it again.
	private(set) var formattedCommandEntries: Set<Int> = []
	var changedFiles: [ChangeFile] = []
	var diff = ""
	var changesByItemID: [String: [FileChange]] = [:]
	var hasAggregateDiff = false
	var liveChangeTurnID: String?
	var reviewSourceRevision = 0

	mutating func cachedTurnPayloadCosts() -> ConversationTurnPayloadCosts
	{
		if turnPayloadCosts == nil
		{
			turnPayloadCosts = ConversationTurnPayloadCosts(turns: loadedTurns)
		}
		return turnPayloadCosts!
	}

	mutating func cachedEntryPayloadCosts() -> ConversationEntryPayloadCosts
	{
		if entryPayloadCosts == nil
		{
			entryPayloadCosts = ConversationEntryPayloadCosts(entries: entries)
		}
		return entryPayloadCosts!
	}

	mutating func entryIndex(for id: String) -> Int?
	{
		if entryIndices == nil
		{
			var indices: [String: Int] = [:]
			for (index, entry) in entries.enumerated() where indices[entry.id] == nil
			{
				indices[entry.id] = index
			}
			entryIndices = indices
		}
		return entryIndices?[id]
	}

	mutating func updateEntry(
		at index: Int,
		hasFormattedCommandBody: Bool = false,
		_ update: (inout ConversationEntry) -> Void
	)
	{
		let id = entries[index].id
		let indices = entryIndices
		var payloadCosts = entryPayloadCosts
		let previousCost = payloadCosts.map
		{
			_ in ConversationEntryPayloadCosts.cost(entries[index])
		}
		var formattedEntries = formattedCommandEntries
		update(&entries[index])
		if let previousCost
		{
			payloadCosts?.replace(
				previousCost,
				with: entries[index]
			)
			entryPayloadCosts = payloadCosts
		}
		if entries[index].id == id
		{
			entryIndices = indices
		}
		if hasFormattedCommandBody
		{
			if !formattedEntries.contains(index)
			{
				formattedEntries.insert(index)
			}
		}
		else if formattedEntries.contains(index)
		{
			formattedEntries.remove(index)
		}
		formattedCommandEntries = formattedEntries
	}

	mutating func appendEntry(
		_ entry: ConversationEntry,
		hasFormattedCommandBody: Bool = false
	)
	{
		let index = entries.count
		var indices = entryIndices
		var payloadCosts = entryPayloadCosts
		var formattedEntries = formattedCommandEntries
		entries.append(entry)
		payloadCosts?.append(entry)
		entryPayloadCosts = payloadCosts
		if indices?[entry.id] == nil
		{
			indices?[entry.id] = index
		}
		entryIndices = indices
		if hasFormattedCommandBody
		{
			formattedEntries.insert(index)
		}
		formattedCommandEntries = formattedEntries
	}
}

enum ThreadManagementOperation
{
	case rename(
		context: OperationContext,
		name: String
	)
	case archive(OperationContext)
	case unarchive(OperationContext)
	case delete(OperationContext)
}

struct ConversationsModel
{
	var threads: [ThreadSummary] = []
	/// Notifications remain authoritative over an already pending list response.
	var observedThreadNames: [String: String?] = [:]
	var selectedConversation: ConversationKey = .newChat
	var content: [ConversationKey: ConversationContentModel] = [:]
	var pendingNewChatContent: [Int: ConversationContentModel] = [:]
	var historyErrors: [String: String] = [:]
	var contentRevisions: [String: Int] = [:]
	var showingArchived = false
	var pendingList: ConversationListOperation?
	var pendingSelection: OperationContext?
	var pendingSelectionPersistence: OperationContext?
	var pendingReads: [ConversationReadKey: ConversationReadOperation] = [:]
	var boundThreadID: String?
	var pendingManagementArchived = false
	var lastAppliedHistoryRequestID: UUID?
	var lastAppliedPageRequestID: UUID?
	var pendingManagement: ThreadManagementOperation?
	var pendingProjectArchive: ProjectArchiveOperation?
	/// Thread key preserves manual/search/jump page deduplication within one workspace store.
	var historyLoads: [String: HistoryLoadOperation] = [:]
	var cacheTime = Date.distantPast
	var cacheAccessCounter = 0
	var cacheOverBudget = false
	var cacheAccounting = ConversationCacheAccounting()
	var turnReferenceIndices: [String: TurnReferenceIndex] = [:]
	var pendingTurnReads: [String: ConversationTurnReadOperation] = [:]
	var error: String?
}

struct ConversationReviewModel
{
	var turns: [ReviewTurn] = []
	var parsedChanges: [String: ReviewParsedChanges] = [:]
	var selectedTurnID: String?
	var sourceRevision = -1
	var markerRevision = 0
	var loadedMarkerSnapshot: [ReviewMarkerIdentity]?
	var markerFingerprints: [ReviewReference: String] = [:]
	var pendingMarkerLoad: ReviewMarkerReadOperation?
	var pendingMarkerWrites: [ReviewReference: ReviewMarkerWriteOperation] = [:]
	var error: String?
}

struct ReviewModel
{
	var conversations: [ConversationKey: ConversationReviewModel] = [:]
	var observationContext: OperationContext?
}

struct ContextNavigationModel
{
	var projectContext = ProjectContext()
	var contextError: String?
	var contextRevision = 0
	var pendingContextLoad: ContextLoadOperation?
	var pendingContextSave: ContextSaveOperation?
	var skillCatalog: SkillCatalog?
	var skillError: String?
	var pendingSkillRefresh: SkillsRefreshOperation?
	var skillRefreshPending = false
	var messageSearch: MessageSearchResults?
	var messageSearchContext: OperationContext?
	var pendingMessageSearch: MessageSearchOperation?
	var searchIndexSource: MessageSearchIndexSource?
	var searchableThreads: [SearchableThread] = []
	var searchIndexRevision = 0
	var navigationTargets: [ConversationJumpTarget] = []
	var pendingSearch: NavigationSearchOperation?
	var searchError: String?
	var pendingJump: ConversationJumpOperation?
	var jumpError: String?
}

struct PreferencesModel
{
	var pendingPreferenceWrites: [PreferenceWrite.Key: OperationContext] = [:]
	var preferenceWriteErrors: [PreferenceWrite.Key: String] = [:]
	var globalModelPreference: ProjectModelPreference?
	var projectModelPreference: ProjectModelPreference?
	var statusMessage: String?
	var selectedModelID: String?
	var selectedEffort: String?
	var runPreferences = RunPreferences.standard
	var hasStoredModelPreference = false
	var models: [ModelOption] = []
	var modelListError: String?
	var accountDescription = "Checking sign-in…"
	var recentProjects: [URL] = []
	var pinnedProjectPaths: Set<String> = []
	var removedProjectPaths: Set<String> = []
	var pinnedTasks: [ThreadSummary] = []
	var projectDisplayNames: [String: String] = [:]
	var pendingModels: OperationContext?
	var pendingAccount: OperationContext?
	var pendingSignIn: OperationContext?
	var persistenceError: String?
}

struct UsageRefreshOperation
{
	let context: OperationContext
	var readsStarted: Int
}

struct UsageModel
{
	var snapshot: AccountRateLimitsSnapshot?
	var fetchedAt: Date?
	var error: String?
	var needsRefresh = true
	var pendingRefresh: UsageRefreshOperation?
	var refreshPending = false
	var freshnessDeadline: Date?
	var pendingDeadline: UsageDeadlineOperation?

	/// Time enters through an action or selector argument, never a model clock read.
	func isStale(
		isConnected: Bool,
		now: Date
	) -> Bool
	{
		guard isConnected, !needsRefresh, error == nil, fetchedAt != nil,
				let freshnessDeadline
		else
		{
			return true
		}
		return now >= freshnessDeadline
	}
}

struct WorkspaceQuitReservation: Equatable
{
	let requestID: UUID
	let reference: WorkspaceLifecycleOwnerReference
}

struct WorkspaceLifecycleModel
{
	var owner: WorkspaceLifecycleOwner?
	var managedWorkspace: TaskWorkspace?
	var managedOwnershipConflict: String?
	var lastCleanupRequestID: UUID?
	var cleanupReservation: WorkspaceCleanupRequest?
	var quitReservation: WorkspaceQuitReservation?
	var isShutdown = false
	var statusMessage: String?
	var backendDiagnostics: BackendDiagnosticsSnapshot?
	var validatedReusableReferences: [ConversationKey: [ComposerContextItem]] = [:]
	var validatedImagePaths: Set<String> = []
	var referenceValidationCandidates: [ConversationKey: [ComposerContextItem]] = [:]
	var pendingSourceStartup: OperationContext?
	var pendingProjectOpening: OperationContext?
	var pendingArchivedSelection: OperationContext?
	var pendingInputPreparation: ComposerInputPreparationOperation?
	var recoveryListRequestID: UUID?
	var bootstrapRequestID: UUID?
	var persistenceFailures: [String: WorkspaceLifecyclePersistenceFailure] = [:]
	var successfulWriteRevisions: [String: Int] = [:]
}

struct WorkspaceLifecyclePersistenceFailure
{
	let revision: Int
	let message: String
}
