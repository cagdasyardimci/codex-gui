import Foundation

extension AppServer
{
	/// A hover reads at most the first and last item pages.
	/// Partial results are never transcript turns.
	func loadTurnPreviewContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	{
		let generation = connectionGeneration
		func loadItemPage(sortedBy direction: String) async throws -> DecodedTurnItemPage
		{
			let result = try await request(
				"thread/items/list",
				params: [
					"threadId": threadId,
					"turnId": reference.id,
					"limit": 100,
					"sortDirection": direction,
				]
			)
			return try await decodeProtocolPayload(
				ProtocolJSONPayload(value: result),
				generation: generation,
				priority: .utility
			)
			{
				payload in
				try TurnItemPageDecoder.decode(
					payload,
					turnID: reference.id
				)
			}
		}
		let firstPage = try await loadItemPage(sortedBy: "asc")
		var items = firstPage.items
		let itemsAreComplete = firstPage.nextCursor == nil
		if !itemsAreComplete
		{
			let lastPage = try await loadItemPage(sortedBy: "desc")
			var seen = Set(items.map(\.id))
			items.append(contentsOf: lastPage.items.reversed().filter
			{
				seen.insert($0.id).inserted
			})
			items = items.filter
			{
				$0.type == "userMessage" || $0.type == "agentMessage"
			}
		}
		try Task.checkCancellation()
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		return CodexTurn(
			id: reference.id,
			status: reference.status,
			items: items,
			error: reference.error,
			startedAt: reference.startedAt,
			completedAt: reference.completedAt,
			durationMs: reference.durationMs,
			itemsAreComplete: itemsAreComplete
		)
	}
}
