import Foundation

extension AppServer
{
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
			serviceTier: nil
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
}
