import Foundation

/// Derived accounting contains no backend or rendering work and retains no payload bodies.
struct ConversationCacheAccounting
{
	struct ContentCosts
	{
		var turns = ConversationTurnPayloadCosts(turns: [])
		var loadedRevision = -1
		var additionalRevision = -1
		var additionalByTurn: [String: Int] = [:]
		var additionalBytes = 0
		var totalBytes = 0
		var gapLoadedRevision = -1
		var gapReferenceRevision = -1
		var gapTurnIDs: [String] = []
	}

	private(set) var content: [String: ContentCosts] = [:]
	private(set) var totalContentBytes = 0
	private(set) var hoverBodies: [String: [String: Int]] = [:]
	private(set) var totalHoverBytes = 0
	private(set) var chatsOverTurnLimit: Set<String> = []
	var hasSynchronizedWorkspace = false

	mutating func synchronize(
		threadID: String,
		content value: inout ConversationContentModel
	)
	{
		var costs = content[threadID] ?? ContentCosts()
		let turnCostsInvalidated = value.turnPayloadCosts == nil
		let entryCostsInvalidated = value.entryPayloadCosts == nil
		if entryCostsInvalidated
		{
			costs.gapLoadedRevision = -1
			costs.gapReferenceRevision = -1
		}
		let turns = value.cachedTurnPayloadCosts()
		let entries = value.cachedEntryPayloadCosts()
		let turnsChanged = turnCostsInvalidated || costs.loadedRevision != value
			.loadedHistoryRevision
		if turnsChanged
		{
			costs.turns = turns
			costs.loadedRevision = value.loadedHistoryRevision
		}
		let shouldRecalculateAdditionalCosts = turnsChanged || entryCostsInvalidated
			|| costs.additionalRevision != entries.additionalRevision
		if shouldRecalculateAdditionalCosts
		{
			costs.additionalByTurn = [:]
			costs.additionalBytes = 0
			for (entryID, bytes) in entries.additionalByEntry
				where !turns.representedEntryIDs.contains(entryID)
			{
				let turnID = ConversationEntryPayloadCosts.turnID(for: entryID)
				costs.additionalByTurn[turnID, default: 0] = ConversationCachePolicy.sum(
					costs.additionalByTurn[turnID, default: 0],
					bytes
				)
				costs.additionalBytes = ConversationCachePolicy.sum(
					costs.additionalBytes,
					bytes
				)
			}
			costs.additionalRevision = entries.additionalRevision
		}
		costs.totalBytes = ConversationCachePolicy.sum(
			turns.totalBytes,
			entries.textBytes,
			costs.additionalBytes
		)
		replace(
			threadID: threadID,
			with: costs
		)
	}

	mutating func removeThread(threadID: String)
	{
		if let removed = hoverBodies.removeValue(forKey: threadID)
		{
			let removedBytes = removed.values.reduce(0)
			{
				ConversationCachePolicy.sum(
					$0,
					$1
				)
			}
			totalHoverBytes = max(
				0,
				totalHoverBytes - removedBytes
			)
		}
		remove(threadID: threadID)
	}

	mutating func remove(threadID: String)
	{
		chatsOverTurnLimit.remove(threadID)
		guard let removed = content.removeValue(forKey: threadID)
		else
		{
			return
		}
		if totalContentBytes == Int.max
		{
			recalculateTotal()
		}
		else
		{
			totalContentBytes -= removed.totalBytes
		}
	}

	mutating func replaceHoverBodies(_ values: [String: [String: Int]])
	{
		hoverBodies = values
		totalHoverBytes = values.values.reduce(0)
		{
			$1.values.reduce($0)
			{
				ConversationCachePolicy.sum(
					$0,
					$1
				)
			}
		}
	}

	mutating func recordHover(
		threadID: String,
		turnID: String,
		bytes: Int?
	)
	{
		let previous = hoverBodies[threadID]?[turnID] ?? 0
		if let bytes
		{
			hoverBodies[threadID, default: [:]][turnID] = bytes
		}
		else
		{
			hoverBodies[threadID]?[turnID] = nil
			if hoverBodies[threadID]?.isEmpty == true
			{
				hoverBodies[threadID] = nil
			}
		}
		totalHoverBytes = ConversationCachePolicy.sum(
			max(
				0,
				totalHoverBytes - previous
			),
			bytes ?? 0
		)
	}

	mutating func recordGaps(
		threadID: String,
		loadedRevision: Int,
		referenceRevision: Int,
		turnIDs: [String]
	)
	{
		content[threadID]?.gapLoadedRevision = loadedRevision
		content[threadID]?.gapReferenceRevision = referenceRevision
		content[threadID]?.gapTurnIDs = turnIDs
	}

	private mutating func replace(
		threadID: String,
		with costs: ContentCosts
	)
	{
		let previous = content[threadID]?.totalBytes ?? 0
		content[threadID] = costs
		if costs.turns.turnIDs.count > ConversationCachePolicy.maximumTurnsPerChat
		{
			chatsOverTurnLimit.insert(threadID)
		}
		else
		{
			chatsOverTurnLimit.remove(threadID)
		}
		if totalContentBytes == Int.max
		{
			recalculateTotal()
		}
		else
		{
			totalContentBytes = ConversationCachePolicy.sum(
				totalContentBytes - previous,
				costs.totalBytes
			)
		}
	}

	private mutating func recalculateTotal()
	{
		totalContentBytes = content.values.reduce(0)
		{
			ConversationCachePolicy.sum(
				$0,
				$1.totalBytes
			)
		}
	}
}
