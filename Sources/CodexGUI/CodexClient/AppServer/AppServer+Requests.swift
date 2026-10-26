import Foundation

// Implements application-facing service requests through the shared transport.
extension AppServer
{
	func accountStatus() async throws -> AccountStatus
	{
		let result = try await request(
			"account/read",
			params: ["refreshToken": false]
		)
		let account = result["account"] as? [String: Any]
		return AccountStatus(
			type: account?["type"] as? String,
			email: account?["email"] as? String,
			requiresOpenAIAuth: result["requiresOpenaiAuth"] as? Bool ?? true,
			planType: account?["planType"] as? String
		)
	}

	func logout() async throws
	{
		_ = try await request(
			"account/logout",
			params: nil
		)
	}

	func accountDescription() async throws -> String
	{
		try await accountStatus().description
	}

	func startBrowserLogin() async throws -> URL
	{
		let result = try await request(
			"account/login/start",
			params: ["type": "chatgpt"]
		)
		guard let urlString = result["authUrl"] as? String, let url = URL(string: urlString)
		else
		{
			throw AppServerError.protocolError("Codex did not return a browser sign-in URL.")
		}
		return url
	}

	func models() async throws -> [ModelOption]
	{
		var modelOptions: [ModelOption] = []
		var cursorTracker = PaginationCursorTracker(
			repeatedCursorMessage: "Codex repeated the model list cursor."
		)
		var cursor: String?
		repeat
		{
			var parameters: [String: Any] = ["limit": 100]
			if let cursor
			{
				parameters["cursor"] = cursor
			}
			let result = try await request(
				"model/list",
				params: parameters
			)
			modelOptions += (result["data"] as? [[String: Any]] ?? [])
				.compactMap(ModelOption.init(json:))
			cursor = try cursorTracker.advance(to: result["nextCursor"] as? String)
		}
		while cursor != nil
		return modelOptions
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		let cwd = directory.standardizedFileURL.path
		let result = try await request(
			"skills/list",
			params: ["cwds": [cwd]]
		)
		guard let entries = result["data"] as? [[String: Any]],
				let entry = entries.first(where:
				{
					$0["cwd"] as? String == cwd
				}),
				let rawSkills = entry["skills"] as? [[String: Any]],
				let rawErrors = entry["errors"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Codex did not return skills for this project.")
		}
		let skills = rawSkills.compactMap(AvailableSkill.init(json:))
		let errors = rawErrors.compactMap(SkillDiscoveryError.init(json:))
		guard skills.count == rawSkills.count, errors.count == rawErrors.count
		else
		{
			throw AppServerError.protocolError("Codex returned invalid skill metadata.")
		}
		return SkillCatalog(
			skills: skills,
			errors: errors
		)
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		let result = try await request(
			"account/rateLimits/read",
			params: [:]
		)
		guard let snapshot = AccountRateLimitsSnapshot(json: result)
		else
		{
			throw AppServerError.protocolError("Codex did not return a rate-limit snapshot.")
		}
		return snapshot
	}

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
		try await conversationList(
			directory: directory,
			archived: archived
		)
	}

	func allThreads(archived: Bool) async throws -> [ThreadSummary]
	{
		try await conversationList(
			directory: nil,
			archived: archived
		)
	}

	private func conversationList(
		directory: URL?,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		let cwd = directory?.standardizedFileURL.path
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
				"limit": 100,
				"sourceKinds": ["appServer", "cli", "vscode"],
			]
			if let cwd
			{
				parameters["cwd"] = cwd
			}
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
					thread in cwd.map
					{
						thread.cwd == $0
					} ?? thread.cwd.hasPrefix("/")
				}
			)
			else
			{
				throw AppServerError
					.protocolError(cwd == nil
						? "Codex returned an invalid checkout in the global conversation list."
						: "Codex returned a conversation from another checkout.")
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

	func startTurn(
		threadId: String,
		text: String,
		model: String? = nil,
		effort: String? = nil
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			text: text,
			model: model,
			effort: effort,
			skills: []
		)
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: [.text(text)],
			model: model,
			effort: effort,
			skills: skills
		)
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: [.text(text)],
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd
		)
	}

	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: nil
		)
	}

	/// An explicit cwd binds this turn and later turns to the task's checkout.
	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: .standard
		)
	}

	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: preferences,
			collaborationMode: nil
		)
	}

	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences,
		collaborationMode: CollaborationMode?
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: preferences,
			collaborationMode: collaborationMode,
			serviceTier: preferences.serviceTierForTurn
		)
	}

	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences,
		collaborationMode: CollaborationMode?,
		serviceTier: String?
	) async throws -> CodexTurn
	{
		let turnServiceTier = try validatedServiceTier(
			serviceTier,
			for: preferences
		)
		let protocolInputs = makeProtocolInputs(
			for: inputs,
			skills: skills
		)

		let parameters = makeTurnStartParameters(
			threadId: threadId,
			protocolInputs: protocolInputs,
			model: model,
			effort: effort,
			cwd: cwd,
			preferences: preferences,
			collaborationMode: collaborationMode,
			serviceTier: turnServiceTier
		)

		let result = try await request(
			"turn/start",
			params: parameters
		)
		guard let turn = result["turn"] as? [String: Any], let parsed = CodexTurn(json: turn)
		else
		{
			throw AppServerError.protocolError("Codex did not return a turn ID.")
		}
		if untitledThreadIDs.remove(threadId) != nil
		{
			startAutomaticTitle(
				for: threadId,
				inputs: inputs,
				model: model
			)
		}
		return parsed
	}

	private func makeTurnStartParameters(
		threadId: String,
		protocolInputs: [[String: Any]],
		model: String?,
		effort: String?,
		cwd: URL?,
		preferences: RunPreferences,
		collaborationMode: CollaborationMode?,
		serviceTier: String
	) -> [String: Any]
	{
		var parameters: [String: Any] = [
			"threadId": threadId,
			"input": protocolInputs,
			"approvalPolicy": preferences.approvalPolicy.rawValue,
			"approvalsReviewer": preferences.approvalsReviewer.rawValue,
			"sandboxPolicy": preferences.sandboxPolicy.protocolValue,
			"serviceTierForTurn": serviceTier,
		]
		if let model
		{
			parameters["model"] = model
		}
		if let effort
		{
			parameters["effort"] = effort
		}
		if let cwd
		{
			parameters["cwd"] = cwd.standardizedFileURL.path
		}
		if let collaborationMode
		{
			parameters["collaborationMode"] = collaborationMode.protocolValue
		}
		return parameters
	}

	private func validatedServiceTier(
		_ serviceTier: String?,
		for preferences: RunPreferences
	) throws -> String
	{
		if let configured = preferences.configurationDefaults?.serviceTier
		{
			return configured
		}
		guard preferences.fastMode
		else
		{
			return "default"
		}
		guard let serviceTier, !serviceTier.isEmpty, serviceTier != "default"
		else
		{
			throw AppServerError.requestRejected("Fast mode requires an advertised service tier.")
		}
		return serviceTier
	}

	private func makeProtocolInputs(
		for inputs: [TurnInput],
		skills: [SkillReference]
	) -> [[String: Any]]
	{
		let skillInvocations = skills.map
		{
			"$\($0.name)"
		}
		let invocation = skillInvocations.joined(separator: " ")

		var turnInputs = inputs
		if !invocation.isEmpty
		{
			if !turnInputs.isEmpty, case .text(let text) = turnInputs[0]
			{
				turnInputs[0] = .text("\(invocation) \(text)")
			}
			else
			{
				turnInputs.insert(
					.text(invocation),
					at: 0
				)
			}
		}

		var protocolInputs = turnInputs.map(\.protocolValue)
		protocolInputs += skills.map
		{
			["type": "skill", "name": $0.name, "path": $0.path]
		}
		return protocolInputs
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		try await steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			inputs: [.text(text)]
		)
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	{
		let result = try await request(
			"turn/steer",
			params: [
				"threadId": threadId,
				"expectedTurnId": expectedTurnId,
				"input": inputs.map(\.protocolValue),
			]
		)
		guard let turnId = result["turnId"] as? String, turnId == expectedTurnId
		else
		{
			throw AppServerError.protocolError("Codex returned an unexpected turn ID for steering.")
		}
		return turnId
	}

	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		_ = try await request(
			"turn/interrupt",
			params: ["threadId": threadId, "turnId": turnId]
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
