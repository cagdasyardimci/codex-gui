import Foundation

/// View proposals are captured with the rendered owner; reducers still decide admission.
enum WorkspaceIntent
{
	case editDraft(String)
	case attachContext(ComposerContextItem)
	case removeContext(String)
	case reuseReference(String)
	case send
	case steer(String)
	case stop
	case slashCommand(SlashCommandInvocation)
	case acknowledgeSlashCommand(SlashCommandPresentationRequest)
	case completeSlashCommand(
		SlashCommandPresentationRequest,
		SlashCommandInvocation
	)
	case recoverFork(
		SlashCommandPresentationRequest,
		ForkRecoveryChoice
	)
	case retryPlanSettings(
		SlashCommandPresentationRequest,
		CollaborationModeKind
	)
	case respond(
		PendingInteraction,
		InteractionResponse
	)

	case newChat
	case newChatInProject(URL)
	case openProject(URL)
	case selectThread(String)
	case selectPinnedTask(ThreadSummary)
	case toggleTaskPin(ThreadSummary)
	case renameTask(
		String,
		String
	)
	case refreshThreads
	case setArchived(Bool)
	case renameThread(String)
	case archiveThread
	case archiveTask(String)
	case deleteTask(String)

	case selectModel(String?)
	case selectEffort(String?)
	case selectApprovalMode(ApprovalMode)
	case setFastMode(Bool)
	case toggleProjectPin(URL)
	case removeProject(URL)
	case archiveProjectChats(URL)
	case renameProject(
		URL,
		String
	)
	case signIn
	case reconnect

	case updateProjectContext(ProjectContext)
	case insertPrompt(String)
	case toggleBookmark(ConversationBookmark)
	case jumpBookmark(ConversationBookmark)
	case jumpTarget(ConversationJumpTarget)
	case jumpHit(MessageSearchHit)
	case search(String)
	case dismissSearch
	case loadMoreSearch
	case acknowledgeJump
	case loadEarlierTurns
	case loadEarlierTurnReferences
	case loadTurnPreview(String)
	case updateConversationViewport(ConversationViewport)

	case selectReview(String)
	case setReviewed(
		Bool,
		ReviewReference
	)
	case prepareChangeRequest(
		ReviewRequestKind,
		ReviewReference
	)

	case selectWorkspace(UUID?)
	case createTask(String)
	case removeWorkspace(UUID)
	case cancelCreation(UUID)

	var scope: Scope
	{
		switch self
		{
		case .slashCommand, .acknowledgeSlashCommand, .completeSlashCommand, .retryPlanSettings,
				.recoverFork,
				.editDraft, .attachContext, .removeContext, .reuseReference, .send, .steer,
				.insertPrompt, .prepareChangeRequest, .createTask, .renameProject, .newChat,
				.newChatInProject, .selectModel, .selectEffort, .selectApprovalMode,
				.setFastMode: return .draft
		case .renameThread, .archiveThread, .loadEarlierTurns, .loadEarlierTurnReferences,
				.loadTurnPreview, .updateConversationViewport,
				.selectReview,
				.setReviewed, .toggleBookmark, .acknowledgeJump: return .conversation
		default: return .owner
		}
	}
	enum Scope: Equatable
	{
		case owner, conversation, draft
	}
}
