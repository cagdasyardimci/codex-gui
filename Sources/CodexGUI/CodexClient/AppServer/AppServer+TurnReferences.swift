import Foundation

extension AppServer
{
	func loadTurnReferences(
		threadId: String,
		cursor: String?
	) async throws -> TurnReferencePage
	{
		let generation = connectionGeneration
		var parameters: [String: Any] = [
			"threadId": threadId,
			"limit": 100,
			"sortDirection": "desc",
			"itemsView": "notLoaded",
		]
		if let cursor
		{
			parameters["cursor"] = cursor
		}
		let result = try await request(
			"thread/turns/list",
			params: parameters
		)
		try Task.checkCancellation()
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		guard let data = result["data"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid turn reference page.")
		}
		let references = data.reversed().compactMap(ConversationTurnReference.init(json:))
		guard references.count == data.count
		else
		{
			throw AppServerError.protocolError("Codex returned a turn reference without an ID.")
		}
		return TurnReferencePage(
			references: references,
			nextCursor: result["nextCursor"] as? String
		)
	}

	func loadTurnContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	{
		let generation = connectionGeneration
		var cursor: String?
		var visited: Set<String> = []
		var items: [CodexItem] = []
		repeat
		{
			var parameters: [String: Any] = [
				"threadId": threadId,
				"turnId": reference.id,
				"limit": 100,
				"sortDirection": "asc",
			]
			if let cursor
			{
				parameters["cursor"] = cursor
			}
			let result = try await request(
				"thread/items/list",
				params: parameters
			)
			try Task.checkCancellation()
			guard generation == connectionGeneration
			else
			{
				throw AppServerError.disconnected
			}
			let payload = ProtocolJSONPayload(value: result)
			let decoding = Task.detached(priority: .userInitiated)
			{
				try TurnItemPageDecoder.decode(
					payload,
					turnID: reference.id
				)
			}
			let page = try await withTaskCancellationHandler
			{
				try await decoding.value
			}
			onCancel:
			{
				decoding.cancel()
			}
			try Task.checkCancellation()
			guard generation == connectionGeneration
			else
			{
				throw AppServerError.disconnected
			}
			items.append(contentsOf: page.items)
			cursor = page.nextCursor
			if let cursor, !visited.insert(cursor).inserted
			{
				throw AppServerError.protocolError("Codex repeated the turn item cursor.")
			}
		}
		while cursor != nil
		return CodexTurn(
			id: reference.id,
			status: reference.status,
			items: items,
			error: reference.error,
			startedAt: reference.startedAt,
			completedAt: reference.completedAt,
			durationMs: reference.durationMs
		)
	}
}
