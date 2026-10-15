import Foundation

struct ConversationViewport: Equatable
{
	var turnIDs: Set<String> = []
	var anchorTurnID: String?
	var firstTurnID: String?
	var lastTurnID: String?
	var nearTop = false
	var nearBottom = false
}
