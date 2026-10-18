import Foundation

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
