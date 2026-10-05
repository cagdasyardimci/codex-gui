import Foundation

/// The navigation index is independent of loaded transcript content and its cursor.
struct TurnReferenceIndex
{
	var references: [ConversationTurnReference] = []
	var nextCursor: String?
	var hasLoadedPage = false
	var pendingRead: TurnReferenceReadOperation?
	var error: String?
	var pendingWindowRead: ConversationTurnReadOperation?
	var windowQueue: [ConversationTurnReference] = []
	var windowError: String?
	var pendingPreviewRead: ConversationTurnReadOperation?
	var navigationProtection: String?
	var viewport = ConversationViewport()
	var access: [String: Int] = [:]
	var previewAccess: [String: Int] = [:]
	var previewCachedAt: [String: Date] = [:]
	var previews: [String: ConversationTurnSummary] = [:]
	var previewTurns: [String: CodexTurn] = [:]
	var previewErrors: [String: String] = [:]
}

struct TurnReferenceReadOperation: Equatable
{
	let context: OperationContext
	let cursor: String?
}

struct ConversationTurnReadOperation: Equatable
{
	let context: OperationContext
	let reference: ConversationTurnReference
	let commandRevision: Int
	var isPreview = false
	var isWindow = false
}
