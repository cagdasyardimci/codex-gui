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
		func page(_ direction: String) async throws -> DecodedTurnItemPage
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
			try Task.checkCancellation()
			guard generation == connectionGeneration
			else
			{
				throw AppServerError.disconnected
			}
			let payload = ProtocolJSONPayload(value: result)
			let decoding = Task.detached(priority: .utility)
			{
				try TurnItemPageDecoder.decode(
					payload,
					turnID: reference.id
				)
			}
			return try await withTaskCancellationHandler
			{
				try await decoding.value
			}
			onCancel:
			{
				decoding.cancel()
			}
		}
		let first = try await page("asc")
		var items = first.items
		let complete = first.nextCursor == nil
		if !complete
		{
			let last = try await page("desc")
			var seen = Set(items.map(\.id))
			items.append(contentsOf: last.items.reversed().filter
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
			itemsAreComplete: complete
		)
	}
}
