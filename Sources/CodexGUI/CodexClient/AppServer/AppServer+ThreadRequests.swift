import Foundation

extension AppServer
{
	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		try await threads(
			for: directory,
			archived: false
		)
	}

	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		let cwd = directory.standardizedFileURL.path
		var threadSummaries: [ThreadSummary] = []
		var seenThreadIDs: Set<String> = []
		var cursorTracker = PaginationCursorTracker(
			repeatedCursorMessage: "Codex repeated the conversation list cursor."
		)
		var cursor: String?
		repeat
		{
			var parameters: [String: Any] = [
				"archived": archived,
				"cwd": cwd,
				"limit": 100,
				"sourceKinds": ["appServer", "cli", "vscode"],
			]
			if let cursor
			{
				parameters["cursor"] = cursor
			}
			let result = try await request(
				"thread/list",
				params: parameters
			)
			guard let rows = result["data"] as? [[String: Any]]
			else
			{
				throw AppServerError.protocolError("Codex returned an invalid conversation list.")
			}
			let page = rows.compactMap(ThreadSummary.init(json:))
			guard page.count == rows.count, page.allSatisfy(
				{
					$0.cwd == cwd
				}
			)
			else
			{
				throw AppServerError
					.protocolError("Codex returned a conversation from another checkout.")
			}
			// The backend can repeat task IDs within a page or across pages.
			threadSummaries += page.filter
			{
				seenThreadIDs.insert($0.id).inserted
			}
			cursor = try cursorTracker.advance(to: result["nextCursor"] as? String)
		}
		while cursor != nil
		return threadSummaries
	}

	func renameThread(
		id: String,
		name: String
	) async throws
	{
		cancelAutomaticTitle(for: id)
		try await sendThreadName(
			id: id,
			name: name
		)
	}

	func sendThreadName(
		id: String,
		name: String
	) async throws
	{
		_ = try await request(
			"thread/name/set",
			params: ["threadId": id, "name": name]
		)
	}

	func deleteThread(id: String) async throws
	{
		cancelAutomaticTitle(for: id)
		_ = try await request(
			"thread/delete",
			params: ["threadId": id]
		)
	}

	func archiveThread(id: String) async throws
	{
		_ = try await request(
			"thread/archive",
			params: ["threadId": id]
		)
	}

	func unarchiveThread(id: String) async throws
	{
		_ = try await request(
			"thread/unarchive",
			params: ["threadId": id]
		)
	}

	func startThread(
		in directory: URL,
		model: String? = nil
	) async throws -> ThreadDetail
	{
		let cwd = directory.standardizedFileURL.path
		var parameters: [String: Any] = ["cwd": cwd]
		if let model
		{
			parameters["model"] = model
		}
		let result = try await request(
			"thread/start",
			params: parameters
		)
		guard let thread = result["thread"] as? [String: Any],
				let summary = ThreadSummary(json: thread),
				summary.cwd == cwd, result["cwd"] as? String == cwd
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid new conversation.")
		}
		untitledThreadIDs.insert(summary.id)
		return ThreadDetail(
			summary: summary,
			turns: [],
			nextTurnsCursor: nil,
			settings: ThreadSettings(json: result)
		)
	}

	func resumeThread(id: String) async throws -> ThreadDetail
	{
		try await resumeThread(
			id: id,
			expectedDirectory: nil
		)
	}

	/// Checks the resumed session's saved cwd before a caller starts another turn.
	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		let result = try await request(
			"thread/resume",
			params: [
				"threadId": id,
				"excludeTurns": true,
			]
		)
		guard let thread = result["thread"] as? [String: Any],
				let summary = ThreadSummary(json: thread), summary.id == id
		else
		{
			throw AppServerError.protocolError("Codex could not resume this conversation.")
		}
		return try await hydrateValidatedThread(
			summary,
			result: result,
			expectedDirectory: expectedDirectory,
			invalidResponseMessage: "Codex could not resume this conversation."
		)
	}

	func readThread(id: String) async throws -> ThreadDetail
	{
		let result = try await request(
			"thread/read",
			params: ["threadId": id]
		)
		guard let thread = result["thread"] as? [String: Any],
				let summary = ThreadSummary(json: thread), summary.id == id
		else
		{
			throw AppServerError.protocolError("Codex could not read this conversation.")
		}
		let page = try await loadTurns(threadId: id)
		return ThreadDetail(
			summary: summary,
			turns: page.turns,
			nextTurnsCursor: page.nextCursor
		)
	}

	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (
		turns: [CodexTurn],
		nextCursor: String?
	)
	{
		try await loadTurns(
			threadId: threadId,
			cursor: cursor
		)
	}

	func loadTurns(
		threadId: String,
		cursor: String? = nil
	) async throws -> (
		turns: [CodexTurn],
		nextCursor: String?
	)
	{
		let generation = connectionGeneration
		var parameters: [String: Any] = [
			"threadId": threadId,
			"limit": ConversationCachePolicy.contentPageSize,
			"sortDirection": "desc",
			"itemsView": "full",
		]
		if let cursor
		{
			parameters["cursor"] = cursor
		}
		let result = try await request(
			"thread/turns/list",
			params: parameters
		)
		let page = try await decodeProtocolPayload(
			ProtocolJSONPayload(value: result),
			generation: generation,
			priority: .userInitiated
		)
		{
			payload in
			try ConversationHistoryDecoder.decode(payload)
		}
		return (page.turns, page.nextCursor)
	}
}
