import Foundation

@MainActor
protocol CodexService: AnyObject
{
	var onEvent: ((AppServerEvent) -> Void)?
	{
		get set
	}
	var onDisconnect: ((String) -> Void)?
	{
		get set
	}
	var backendDiagnostics: BackendDiagnosticsSnapshot
	{
		get
	}

	func executableVersion() async throws -> String
	func remoteControlStatus() async throws -> RemoteControlStatus
	func setRemoteControlEnabled(_ enabled: Bool) async throws -> RemoteControlStatus
	func startRemoteControlPairing() async throws -> RemoteControlPairing
	func remoteControlPairingClaimed(_ pairing: RemoteControlPairing) async throws -> Bool
	func remoteControlClients(environmentID: String) async throws -> [RemoteControlClient]
	func revokeRemoteControlClient(
		environmentID: String,
		clientID: String
	) async throws
	func connect() async throws
	func disconnect()
	func accountStatus() async throws -> AccountStatus
	func startBrowserLogin() async throws -> URL
	func models() async throws -> [ModelOption]
	func skills(for directory: URL) async throws -> SkillCatalog
	func rateLimits() async throws -> AccountRateLimitsSnapshot
	func allThreads(archived: Bool) async throws -> [ThreadSummary]
	func threads(for directory: URL) async throws -> [ThreadSummary]
	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	func renameThread(
		id: String,
		name: String
	) async throws
	func deleteThread(id: String) async throws
	func archiveThread(id: String) async throws
	func unarchiveThread(id: String) async throws
	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	func resumeThread(id: String) async throws -> ThreadDetail
	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	func readThread(id: String) async throws -> ThreadDetail
	func forkThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	func compactThread(id: String) async throws
	func startReview(
		threadId: String,
		target: ReviewTarget
	) async throws -> ReviewStartResult
	func startReview(
		threadId: String,
		target: ReviewTarget,
		delivery: ReviewDelivery
	)
		async throws -> ReviewStartResult
	func collaborationModes() async throws -> [CollaborationModePreset]
	func updateThreadSettings(
		id: String,
		settings: ThreadSettingsUpdate
	) async throws
	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (
		turns: [CodexTurn],
		nextCursor: String?
	)
	func loadTurnReferences(
		threadId: String,
		cursor: String?
	) async throws -> TurnReferencePage
	func loadTurnPreviewContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	func loadTurnContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws
		-> CodexTurn
	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws
		-> CodexTurn
	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?
	) async throws -> CodexTurn
	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences
	) async throws -> CodexTurn
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
	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	func respondAndWait(
		to requestID: String,
		with response: InteractionResponse
	) async throws
	/// Nil means this implementation cannot establish whether a response reached its transport.
	func responseMayHaveBeenSent(to requestID: String) -> Bool?
}

extension CodexService
{
	func loadTurnReferences(
		threadId: String,
		cursor: String?
	) async throws -> TurnReferencePage
	{
		TurnReferencePage(
			references: [],
			nextCursor: nil
		)
	}

	func loadTurnPreviewContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	{
		try await loadTurnContents(
			threadId: threadId,
			reference: reference
		)
	}

	func loadTurnContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	{
		throw AppServerError.requestRejected("This Codex service cannot load an individual turn.")
	}

	func responseMayHaveBeenSent(to requestID: String) -> Bool?
	{
		nil
	}

	func respondAndWait(
		to requestID: String,
		with response: InteractionResponse
	) async throws
	{
		try Task.checkCancellation()
		try respond(
			to: requestID,
			with: response
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
		guard !preferences.fastMode
		else
		{
			throw AppServerError
				.requestRejected("This Codex service cannot select a fast service tier.")
		}
		guard serviceTier == nil || serviceTier == "default"
		else
		{
			throw AppServerError.requestRejected("This Codex service cannot select a service tier.")
		}
		return try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: preferences,
			collaborationMode: collaborationMode
		)
	}

	func forkThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		throw AppServerError.requestRejected("This Codex service cannot fork conversations.")
	}

	func compactThread(id: String) async throws
	{
		throw AppServerError.requestRejected("This Codex service cannot compact conversations.")
	}

	func startReview(
		threadId: String,
		target: ReviewTarget
	) async throws -> ReviewStartResult
	{
		try await startReview(
			threadId: threadId,
			target: target,
			delivery: .inline
		)
	}

	func startReview(
		threadId: String,
		target: ReviewTarget,
		delivery: ReviewDelivery
	)
		async throws -> ReviewStartResult
	{
		throw AppServerError.requestRejected("This Codex service cannot start a review.")
	}

	func collaborationModes() async throws -> [CollaborationModePreset]
	{
		throw AppServerError.requestRejected("This Codex service cannot list collaboration modes.")
	}

	func updateThreadSettings(
		id: String,
		settings: ThreadSettingsUpdate
	) async throws
	{
		throw AppServerError.requestRejected("This Codex service cannot update thread settings.")
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
		guard collaborationMode == nil
		else
		{
			throw AppServerError
				.requestRejected("This Codex service cannot set collaboration mode.")
		}
		return try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: preferences
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
		guard preferences == .standard
		else
		{
			throw AppServerError.protocolError(
				"This Codex service does not support the selected approval policy or fast mode."
			)
		}
		return try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd
		)
	}

	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		let detail = try await resumeThread(id: id)
		try CheckoutIdentity.validate(
			cwd: detail.summary.cwd,
			expectedDirectory: expectedDirectory
		)
		return detail
	}

	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?
	) async throws -> CodexTurn
	{
		guard cwd == nil
		else
		{
			throw AppServerError.protocolError(
				"This Codex service cannot start a turn in a verified checkout."
			)
		}
		return try await startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills
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
		guard inputs.count == 1, case .text(let text) = inputs[0]
		else
		{
			throw AppServerError
				.protocolError("This Codex service cannot send context attachments.")
		}
		return try await startTurn(
			threadId: threadId,
			text: text,
			model: model,
			effort: effort,
			skills: skills
		)
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	{
		guard inputs.count == 1, case .text(let text) = inputs[0]
		else
		{
			throw AppServerError.protocolError(
				"This Codex service cannot steer with context attachments."
			)
		}
		return try await steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			text: text
		)
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		throw AppServerError.protocolError("This Codex service cannot list skills.")
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		throw AppServerError.protocolError("This Codex service cannot read rate limits.")
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	{
		guard skills.isEmpty
		else
		{
			throw AppServerError.protocolError("This Codex service cannot invoke skills.")
		}
		return try await startTurn(
			threadId: threadId,
			text: text,
			model: model,
			effort: effort
		)
	}

	func allThreads(archived: Bool) async throws -> [ThreadSummary]
	{
		throw AppServerError.protocolError("This Codex service cannot list chats across projects.")
	}

	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		guard !archived
		else
		{
			throw AppServerError
				.protocolError("This Codex service cannot list archived conversations.")
		}
		return try await threads(for: directory)
	}

	func renameThread(
		id: String,
		name: String
	) async throws
	{
		throw AppServerError.protocolError("This Codex service cannot rename conversations.")
	}

	func deleteThread(id: String) async throws
	{
		throw AppServerError.protocolError("This Codex service cannot delete conversations.")
	}

	func archiveThread(id: String) async throws
	{
		throw AppServerError.protocolError("This Codex service cannot archive conversations.")
	}

	func unarchiveThread(id: String) async throws
	{
		throw AppServerError.protocolError("This Codex service cannot unarchive conversations.")
	}
}

// Older and fixture services expose an explicit unsupported result.
extension CodexService
{
	func remoteControlStatus() async throws -> RemoteControlStatus
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
	func setRemoteControlEnabled(_ enabled: Bool) async throws -> RemoteControlStatus
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
	func startRemoteControlPairing() async throws -> RemoteControlPairing
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
	func remoteControlClients(environmentID: String) async throws -> [RemoteControlClient]
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
	func revokeRemoteControlClient(
		environmentID: String,
		clientID: String
	) async throws
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
}

extension CodexService
{
	func remoteControlPairingClaimed(_ pairing: RemoteControlPairing) async throws -> Bool
	{
		throw AppServerError.protocolError("Remote access requires a compatible Codex CLI.")
	}
}
