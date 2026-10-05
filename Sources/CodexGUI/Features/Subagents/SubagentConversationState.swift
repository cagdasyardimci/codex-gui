import Foundation

struct SubagentConversationState
{
	var agent: CodexSubagentActivity?
	var requestID: Int?
	var entries: [ConversationEntry] = []
	var nextCursor: String?
	var settings: ThreadSettings?
	var error: String?
	var isLoading = false
	var turnTimings: [ConversationTurnTiming] = []
	var failedPaginationCursor: String?
	var hasLoadedEarlierPages = false
	var loadedTurns: [CodexTurn] = []

	var selectedThreadID: String?
	{
		agent?.conversationThreadID
	}
}
