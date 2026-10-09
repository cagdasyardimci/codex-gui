import Foundation

/// Descriptions capture input values. They never capture a mutable application model.
enum WorkspaceEffect
{
	case restoreSourceStartup(OperationContext)
	case readReviewMarkers(ReviewMarkerReadOperation)
	case writeReviewMarker(ReviewMarkerWriteOperation)
	case normalizeProjectPreference(
		OperationContext,
		URL,
		name: String?
	)
	case prepareProjectOpening(
		OperationContext,
		URL,
		selectedThreadID: String? = nil
	)
	case restoreArchivedSelection(
		OperationContext,
		archived: Bool
	)
	case validateComposerInput(ComposerInputPreparationOperation)
	case releaseUnsentSubmission(ComposerSubmission)
	case restorePreferences(OperationContext)
	case restoreComposer(OperationContext)
	case readBackendDiagnostics(OperationContext)
	case validateReusableReferences(ReusableReferenceValidationOperation)
	case connect(OperationContext)
	case disconnect
	case restoreExecution(
		OperationContext,
		selectedThreadID: String?
	)
	case interrupt(InterruptionOperation)
	case steer(SteeringOperation)
	case respond(InteractionResponseOperation)
	case readRecovery(ReconciliationOperation)
	case readCompletedHistory(ReconciliationOperation)
	case persistCommands(
		OperationContext,
		[TaskCommandOwnership]
	)
	case persistExecutionRecovery(
		OperationContext,
		[String]
	)
	case persistPreparedConversation(PreparedConversationWrite)
	case acknowledgeSubmission(SubmissionAcknowledgementWrite)
	case releaseSubmission(WorkspaceSubmissionReleaseOperation)
	case taskFinished
	case readExecutableVersion(OperationContext)
	case readSelection(OperationContext)
	case readConversationHistory(ConversationReadOperation)
	case readConversationPage(HistoryLoadOperation)
	case readTurnReferences(TurnReferenceReadOperation)
	case readTurnContents(ConversationTurnReadOperation)
	case promoteTurnContents(ConversationTurnReadPromotion)
	case captureConversationRead(ConversationReadFollowUp)
	case expireTurnPreviews(OperationContext)
	case readConversationList(ConversationListOperation)
	case manageConversation(ThreadManagementOperation)
	case archiveProjectChats(ProjectArchiveOperation)
	case forkConversation(SlashCommandPresentationRequest)
	case compactConversation(ComposerCommandTurnOperation)
	case startConversationReview(ComposerCommandTurnOperation)
	case updateCommandSettings(ComposerCommandSettingsOperation)
	case persistConversationSelection(
		OperationContext,
		threadID: String?
	)
	case readAccount(OperationContext)
	case loadProjectContext(ContextLoadOperation)
	case saveProjectContext(ContextSaveOperation)
	case readSkills(SkillsRefreshOperation)
	case searchMessages(
		MessageSearchOperation,
		threads: [SearchableThread],
		totalThreadCount: Int
	)
	case cancelMessageSearch(MessageSearchOperation)
	case readModels(OperationContext)
	case beginSignIn(OperationContext)
	case persistPreference(PreferenceWrite)
	case readUsage(UsageReadOperation)
	case scheduleUsageDeadline(UsageDeadlineOperation)
	case cancelUsageDeadline(UsageDeadlineOperation)
	case cancelUsageRefresh(OperationContext)
	case prepareSubmission(ComposerSubmission)
	case startSubmission(PreparedSubmission)
	case bindGitTurnBaseline(GitTurnBaselineBindingOperation)
	case discardGitTurnBaseline(GitTurnBaselineDiscardOperation)
	case persistDraft(WorkspaceDraftWrite)
	case subscribe(OperationContext)
	case detachSubscription
	case cancel(OperationContext)
}

struct PreparedConversationWrite
{
	let prepared: PreparedSubmission
	let draft: ComposerDraft
	let selectThread: Bool
	var clearSource = true
}

struct SubmissionAcknowledgementWrite
{
	let submission: ComposerSubmission
	let threadID: String
	/// Nil preserves the draft. A value is the reducer-captured replacement.
	let draft: ComposerDraft?
}

struct WorkspaceSentReferenceWrite
{
	let context: OperationContext
	let threadID: String
	let items: [ComposerContextItem]
}

struct SubmissionDraftAcknowledgement
{
	let submission: ComposerSubmission
	let threadID: String
	let cleared: Bool
	var references: [ComposerContextItem]? = nil
}

struct WorkspaceSubmissionReleaseOperation
{
	let context: OperationContext
	let submission: ComposerSubmission
}

struct SubmissionReservationRelease
{
	let submission: ComposerSubmission
	let threadID: String?
	let references: [ComposerContextItem]?
	let released: Bool
}

struct PreparedSubmission
{
	let submission: ComposerSubmission
	let thread: ThreadDetail
	var workspace: TaskWorkspace? = nil
}

struct GitTurnBaselineBindingOperation
{
	let context: OperationContext
	let reference: GitTurnBaselineReference
	let turnID: String
}

struct PendingGitTurnBaselineCapture: Sendable
{
	let context: OperationContext
	let reference: GitTurnBaselineReference
	let previousTurnIDs: Set<String>
}

struct GitTurnBaselineDiscardOperation
{
	let context: OperationContext
	let reference: GitTurnBaselineReference
}

struct GitTurnBaselineBindingStatus
{
	let context: OperationContext
	let turnID: String
	var result: GitTurnBaselineResult?
}

struct WorkspaceDraftWrite
{
	let context: OperationContext
	let conversation: ConversationKey
	let draft: ComposerDraft
}
