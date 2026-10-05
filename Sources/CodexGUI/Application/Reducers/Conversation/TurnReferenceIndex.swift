import Foundation

/// The navigation index is independent of loaded transcript content and its cursor.
struct TurnReferenceIndex
{
	var references: [ConversationTurnReference] = []
	{
		didSet
		{
			referenceRevision += 1
			referencePositions = nil
		}
	}
	private(set) var referenceRevision = 0
	private(set) var referencePositions: [String: Int]?
	var nextCursor: String?
	var hasLoadedPage = false
	var pendingRead: TurnReferenceReadOperation?
	var error: String?
	var pendingWindowRead: ConversationTurnReadOperation?
	var windowQueue: [ConversationTurnReference] = []
	var windowError: String?
	var pendingPreviewRead: ConversationTurnReadOperation?
	var pendingPreviewPromotion: ConversationTurnReadPromotion?
	var navigationProtection: String?
	var viewport = ConversationViewport()
	var access: [String: Int] = [:]
	var previewAccess: [String: Int] = [:]
	var previewCachedAt: [String: Date] = [:]
	var previews: [String: ConversationTurnPreview] = [:]
	var previewTurns: [String: CodexTurn] = [:]
	var previewErrors: [String: String] = [:]

	mutating func cachedReferencePositions() -> [String: Int]
	{
		if let referencePositions
		{
			return referencePositions
		}
		var positions: [String: Int] = [:]
		positions.reserveCapacity(references.count)
		for (offset, reference) in references.enumerated() where positions[reference.id] == nil
		{
			positions[reference.id] = offset
		}
		referencePositions = positions
		return positions
	}
}

struct TurnReferenceReadOperation: Equatable
{
	let context: OperationContext
	let cursor: String?
	var summaryOwnership: ConversationSummaryOwnership? = nil
}

struct ConversationTurnReadOperation: Equatable
{
	let context: OperationContext
	let reference: ConversationTurnReference
	let commandRevision: Int
	var isPreview = false
	var isWindow = false
}
