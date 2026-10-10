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
			guard let metadata = CodexTurn.Metadata(json: rawTurn)
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
				metadata: metadata,
				items: items
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
