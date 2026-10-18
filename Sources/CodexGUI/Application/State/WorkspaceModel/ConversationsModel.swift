import Foundation

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
