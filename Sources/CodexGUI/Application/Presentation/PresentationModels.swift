import Foundation

enum ConversationEntryKind
{
	case user
	case agent
	case command
	case tool
	case notice
}

struct ConversationEntry: Equatable
{
	let id: String
	let kind: ConversationEntryKind
	var title: String
	var body: String
	var attachmentPreviewTitle: String? = nil
	var isExpandable: Bool = false
	var activity: ConversationActivity? = nil
	var imageAttachments: [UserMessageReference] = []
	var sourceReferences: [UserMessageReference] = []
	var sourceActivity: ConversationSourceActivity? = nil

	static func == (lhs: Self, rhs: Self) -> Bool
	{
		lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.title == rhs.title
			&& lhs.body.utf8.elementsEqual(rhs.body.utf8)
			&& lhs.attachmentPreviewTitle == rhs.attachmentPreviewTitle
			&& lhs.isExpandable == rhs.isExpandable && lhs.activity == rhs.activity
			&& lhs.imageAttachments == rhs.imageAttachments
			&& lhs.sourceReferences == rhs.sourceReferences
			&& lhs.sourceActivity == rhs.sourceActivity
	}
}

struct ChangeFile: Equatable
{
	let path: String
	let status: String
}

struct TaskWorkspaceChoice: Equatable
{
	let id: UUID
	let title: String
	let checkoutPath: String
	let branch: String
	let sourceWasDirty: Bool
	let phase: TaskWorkspacePhase
	let executionState: ExecutionState?
	let issue: String?
	let canRemoveCheckout: Bool
}

struct ConversationSnapshot
{
	var turnReferences: [ConversationTurnReference] = []
	var turnPreviews: [ConversationTurnPreview] = []
	var turnPreviewErrors: [String: String] = [:]
	var canLoadEarlierTurnReferences = false
	var turnTimings: [ConversationTurnTiming] = []
	var workspaceOwner: WorkspaceLifecycleOwnerReference? = nil
	var workspaceSelectionEpoch = 0
	var composerDraftLifetime = 0
	let projectPath: String?
	let threads: [ThreadSummary]
	var sidebarThreads: [ThreadSummary]? = nil
	var sidebarListLoading = false
	var sidebarListError: String? = nil
	var sidebarConnectionGeneration: Int? = nil
	let selectedThreadID: String?
	let entries: [ConversationEntry]
	let canLoadEarlierTurns: Bool
	let changedFiles: [ChangeFile]
	let diff: String
	var activeTurnDiff: String? = nil
	let draft: String
	var draftContext: [ComposerContextItem] = []
	var reusableReferences: [ComposerContextItem] = []
	let canSend: Bool
	var chatLocked = false
	var chatLockRetrying = false
	let accountDescription: String
	var accountStatus: AccountStatus? = nil
	var accountActionPending = false
	var canLogOut = false
	var accountActionError: String? = nil
	let backendDescription: String
	let executionState: ExecutionState
	let statusMessage: String?
	let models: [ModelOption]
	let selectedModelID: String?
	let selectedEffort: String?
	let pendingInteractions: [PendingInteraction]
	let recentProjects: [URL]
	var approvalMode: ApprovalMode = .askForApproval
	var configurationDefaults: RunConfigurationDefaults? = nil
	var fastMode = false
	var pinnedProjectPaths: Set<String> = []
	var removedProjectPaths: Set<String> = []
	var pinnedTasks: [ThreadSummary] = []
	var projectDisplayNames: [String: String] = [:]
	var preferenceWarning: String? = nil
	var showingArchived = false
	var canManageThreads = false
	/// Nil supports legacy snapshots; runtime publishes eligibility for every known target.
	var threadManagementAvailability: [String: Bool]? = nil
	var activeThreadID: String? = nil
	var activeTurnID: String? = nil
	/// Exact latest source turn, including turns that reported no file changes.
	var lastGitTurnID: String? = nil
	/// The latest editing identity remains available after its transcript payload is evicted.
	var reportedGitTurnID: String? = nil
	/// Nil means unavailable or incomplete; an empty array is a completed authoritative result.
	var reportedGitChanges: [FileChange]? = nil
	var gitTurnBaselineRevision = 0
	var gitTurnBaselineFailure: GitComparisonFailure? = nil
	var activeExecutionState: ExecutionState? = nil
	var taskOutcomeUncertain = false
	var threadExecutions: [String: ThreadExecutionPresentation] = [:]
	var activeExecutionCount: Int? = nil
	var canSteer = false
	var activePlan: TurnPlanUpdate? = nil
	var activeActivity: String? = nil
	var skillCatalog: SkillCatalog? = nil
	var skillError: String? = nil
	var usage: AccountRateLimitsSnapshot? = nil
	var usageFetchedAt: Date? = nil
	var usageIsStale = true
	var usageError: String? = nil
	var reviewTurns: [ReviewTurn] = []
	var selectedReviewTurnID: String? = nil
	var selectedReview: ReviewTurn? = nil
	var reviewedReferences: Set<ReviewReference> = []
	var projectContext = ProjectContext()
	var projectContextError: String? = nil
	var messageSearch: MessageSearchResults? = nil
	var navigationTargets: [ConversationJumpTarget] = []
	var pendingJumpItemID: String? = nil
	var jumpLoading = false
	var jumpError: String? = nil
	var searchLoading = false
	var searchError: String? = nil
	var taskWorkspaces: [TaskWorkspaceChoice] = []
	var selectedTaskWorkspaceID: UUID? = nil
	var taskStatusSummary: String? = nil
	var taskWorkspaceMessage: String? = nil
	var slashCommandUnavailableReasons: [SlashCommandID: String] = [:]
	var planMode = false
	var planModeStatus: String? = nil
	var threadTokenUsage: ThreadTokenUsage? = nil
	var threadStatus: ThreadStatus? = nil
	var threadSettings: ThreadSettings? = nil
}
