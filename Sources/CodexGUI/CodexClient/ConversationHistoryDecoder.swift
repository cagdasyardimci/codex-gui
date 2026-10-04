import Foundation

struct DecodedConversationHistory: Sendable
{
	let turns: [CodexTurn]
	let nextCursor: String?
}

enum ConversationHistoryDecoder
{
	static func decode(
		_ payload: ProtocolJSONPayload,
		isCancelled: () -> Bool =
		{
			Task.isCancelled
		}
	) throws -> DecodedConversationHistory
	{
		let rawTurns = payload.value["data"] as? [[String: Any]] ?? []
		var turns: [CodexTurn] = []
		for rawTurn in rawTurns.reversed()
		{
			try checkCancellation(isCancelled)
			// Reuse metadata defaults and check cancellation throughout large item arrays.
			// Invalid turns and items retain the existing compactMap behavior.
			var metadataJSON = rawTurn
			metadataJSON.removeValue(forKey: "items")
			guard let metadata = CodexTurn(json: metadataJSON)
			else
			{
				continue
			}
			var items: [CodexItem] = []
			for rawItem in rawTurn["items"] as? [[String: Any]] ?? []
			{
				try checkCancellation(isCancelled)
				if let item = CodexItem(json: rawItem)
				{
					items.append(item)
				}
			}
			turns.append(CodexTurn(
				id: metadata.id,
				status: metadata.status,
				items: items,
				error: metadata.error,
				startedAt: metadata.startedAt,
				completedAt: metadata.completedAt,
				durationMs: metadata.durationMs
			))
		}
		try checkCancellation(isCancelled)
		return DecodedConversationHistory(
			turns: turns,
			nextCursor: payload.value["nextCursor"] as? String
		)
	}

	private static func checkCancellation(_ isCancelled: () -> Bool) throws
	{
		if isCancelled()
		{
			throw CancellationError()
		}
	}
}
