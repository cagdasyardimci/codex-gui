import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class MockCodexService: CodexService
{
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	private var readinessObservers: [UUID: @MainActor () -> Void] = [:]

	/// Mock counters and installed continuations do not necessarily publish store state.
	@discardableResult
	func observeReadiness(_ observer: @escaping @MainActor () -> Void) -> UUID
	{
		let id = UUID()
		readinessObservers[id] = observer
		observer()
		return id
	}

	func removeReadinessObserver(_ id: UUID)
	{
		readinessObservers.removeValue(forKey: id)
	}

	private func publishReadiness()
	{
		for observer in Array(readinessObservers.values)
		{
			observer()
		}
	}

	func awaitReadiness(matching predicate: @escaping @MainActor () -> Bool) async -> Bool
	{
		var observation: UUID?
		let stream = AsyncStream<Void>
		{
			continuation in
			observation = observeReadiness
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
		}
		for await _ in stream
		{
			break
		}
		if let observation
		{
			removeReadinessObserver(observation)
		}
		return predicate()
	}
	var backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: "codex-cli 0.153.2",
		exitCode: nil,
		stderrTail: ""
	)
	private var fixtureDirectory = URL(fileURLWithPath: "/tmp")
	func configureCheckout(_ directory: URL)
	{
		fixtureDirectory = directory
	}
	var thread: ThreadSummary
	{
		ThreadSummary(json: [
			"id": "thread-1",
			"name": "Fixture conversation",
			"preview": "Fixture conversation",
			"cwd": fixtureDirectory.path,
			"status": ["type": "idle"],
		])!
	}
	var otherThread: ThreadSummary?
	var savedTurns: [CodexTurn] = []
	var turnsByThreadID: [String: [CodexTurn]] = [:]
	var readNextCursor: String?
	var earlierPages: [String: (turns: [CodexTurn], nextCursor: String?)] = [:]
	var earlierReadCursors: [String] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var turnReferencePages: [String: TurnReferencePage] = [:]
	var turnReferenceReads: [(threadID: String, cursor: String?)] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var referencedTurnContents: [String: CodexTurn] = [:]
	var suspendTurnContentRead = false
	var pendingTurnContentRead: CheckedContinuation<CodexTurn, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var turnContentReads: [(threadID: String, turnID: String)] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendTurnReferenceRead = false
	var pendingTurnReferenceRead: CheckedContinuation<TurnReferencePage, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var earlierReadsToSuspend = 0
	var suspendedEarlierReads:
		[Int: CheckedContinuation<(turns: [CodexTurn], nextCursor: String?), Error>] = [:]
	{
		didSet
		{
			publishReadiness()
		}
	}
	var nextTurn = CodexTurn(json: ["id": "turn-1", "status": "inProgress", "items": []])!
	var suspendThreadStart = false
	var pendingThreadStart: CheckedContinuation<ThreadDetail, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendTurnStart = false
	var pendingTurnStart: CheckedContinuation<CodexTurn, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var turnStartCount = 0
	{
		didSet
		{
			publishReadiness()
		}
	}
	var capturedTurnPreferences: [
		(modelID: String?, effort: String?, preferences: RunPreferences)
	] =
		[]
	var capturedTurnServiceTiers: [String?] = []
	var startTurnError: Error?
	var readThreadError: Error?
	var remoteControlEnableRequests: [Bool] = []
	var readThreadCount = 0
	{
		didSet
		{
			publishReadiness()
		}
	}
	var readThreadIDs: [String] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var threadListCount = 0
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendNextRead = false
	var pendingRead: CheckedContinuation<ThreadDetail, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendInterrupt = false
	var pendingInterrupt: CheckedContinuation<Void, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendEarlierRead = false
	var pendingEarlierRead: CheckedContinuation<(turns: [CodexTurn], nextCursor: String?), Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var interruptedTurnIDs: [String] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var steeredTurns: [(threadID: String, turnID: String, text: String)] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var steerError: Error?
	var steerAcknowledgedTurnID: String?
	var suspendSteer = false
	var pendingSteer: CheckedContinuation<String, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var respondedRequestIDs: [String] = []
	var beforeResponseReturns: (() -> Void)?
	var responseError: Error?
	var availableModels: [ModelOption] = []
	var availableSkills: [AvailableSkill] = []
	var skillReadCount = 0
	var suspendedSkillReadNumbers: Set<Int> = []
	var pendingSkillReads: [Int: CheckedContinuation<SkillCatalog, Error>] = [:]
	private var skillReadWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

	func waitForSkillRead(_ number: Int) async
	{
		guard skillReadCount < number
		else
		{
			return
		}
		await withCheckedContinuation
		{
			skillReadWaiters[number, default: []].append($0)
		}
	}
	var sentTurnRequests: [(text: String, skills: [SkillReference])] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var sentInputRequests: [[TurnInput]] = []
	var steeredInputRequests: [[TurnInput]] = []
	var rateLimitReadCount = 0
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendNextRateLimitRead = false
	var suspendRateLimitReadNumbers: Set<Int> = []
	var rateLimitSnapshotsByReadNumber: [Int: AccountRateLimitsSnapshot] = [:]
	var pendingRateLimitRead: CheckedContinuation<AccountRateLimitsSnapshot, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var fixtureRateLimits: AccountRateLimitsSnapshot
	{
		AccountRateLimitsSnapshot(json: [
			"rateLimits": ["primary": ["usedPercent": 20.0]]
		])!
	}
	var modelsError: Error?
	var suspendVersion = false
	var pendingVersion: CheckedContinuation<String, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var suspendConnection = false
	var pendingConnection: CheckedContinuation<Void, Error>?
	{
		didSet
		{
			publishReadiness()
		}
	}
	var connectionCount = 0
	var archivedThreadIDs: [String] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var unarchivedThreadIDs: [String] = []
	{
		didSet
		{
			publishReadiness()
		}
	}
	var renamedThreads: [(String, String)] = []
	{
		didSet
		{
			publishReadiness()
		}
	}

	func executableVersion() async throws -> String
	{
		if suspendVersion
		{
			return try await withCheckedThrowingContinuation
			{
				pendingVersion = $0
			}
		}
		return "codex-cli 0.153.2"
	}

	func connect() async throws
	{
		connectionCount += 1
		if suspendConnection
		{
			try await withCheckedThrowingContinuation
			{
				pendingConnection = $0
			}
		}
	}

	func disconnect()
	{
	}

	func accountStatus() async throws -> AccountStatus
	{
		AccountStatus(
			type: "chatgpt",
			email: nil,
			requiresOpenAIAuth: true
		)
	}

	func startBrowserLogin() async throws -> URL
	{
		URL(string: "https://example.com/login")!
	}

	func models() async throws -> [ModelOption]
	{
		if let modelsError
		{
			throw modelsError
		}
		return availableModels
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		skillReadCount += 1
		let number = skillReadCount
		for waiter in skillReadWaiters.removeValue(forKey: number) ?? []
		{
			waiter.resume()
		}
		if suspendedSkillReadNumbers.contains(number)
		{
			return try await withCheckedThrowingContinuation
			{
				pendingSkillReads[number] = $0
			}
		}
		return SkillCatalog(
			skills: availableSkills,
			errors: []
		)
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		rateLimitReadCount += 1
		let shouldSuspendRead =
			suspendNextRateLimitRead || suspendRateLimitReadNumbers.contains(rateLimitReadCount)
		if shouldSuspendRead
		{
			suspendNextRateLimitRead = false
			return try await withCheckedThrowingContinuation
			{
				continuation in
				pendingRateLimitRead = continuation
			}
		}
		return rateLimitSnapshotsByReadNumber[rateLimitReadCount] ?? fixtureRateLimits
	}

	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		fixtureDirectory = directory
		return activeThreadSummaries(in: directory)
	}

	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		fixtureDirectory = directory
		threadListCount += 1
		if archived
		{
			return archivedThreadIDs.contains(thread.id) ? [thread] : []
		}

		return activeThreadSummaries(in: directory)
	}

	private func activeThreadSummaries(in directory: URL) -> [ThreadSummary]
	{
		var summaries = [thread]
		if let otherThread
		{
			summaries.append(scopedSummary(
				otherThread,
				directory: directory
			))
		}
		return summaries
	}

	func renameThread(
		id: String,
		name: String
	) async throws
	{
		renamedThreads.append((id, name))
	}

	func archiveThread(id: String) async throws
	{
		archivedThreadIDs.append(id)
	}

	func unarchiveThread(id: String) async throws
	{
		unarchivedThreadIDs.append(id)
	}

	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		fixtureDirectory = directory
		if suspendThreadStart
		{
			let detail: ThreadDetail = try await withCheckedThrowingContinuation
			{
				pendingThreadStart = $0
			}
			return scopedDetail(
				detail,
				directory: directory
			)
		}
		return
			ThreadDetail(
				summary: thread,
				turns: [],
				nextTurnsCursor: nil
			)
	}

	func resumeThread(id: String) async throws -> ThreadDetail
	{
		try await readThread(id: id)
	}

	func setRemoteControlEnabled(_ enabled: Bool) async throws -> RemoteControlStatus
	{
		remoteControlEnableRequests.append(enabled)
		return RemoteControlStatus(
			status: enabled ? .connected : .disabled,
			serverName: "Fixture Mac",
			installationId: "fixture-installation",
			environmentId: enabled ? "fixture-environment" : nil
		)
	}

	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		if let expectedDirectory
		{
			fixtureDirectory = expectedDirectory
		}
		let detail = try await resumeThread(id: id)
		try CheckoutIdentity.validate(
			cwd: detail.summary.cwd,
			expectedDirectory: expectedDirectory
		)
		return detail
	}

	private func scopedSummary(
		_ summary: ThreadSummary,
		directory: URL
	) -> ThreadSummary
	{
		guard summary.cwd == "/tmp"
		else
		{
			return summary
		}
		var json: [String: Any] = [
			"id": summary.id,
			"cwd": directory.path,
			"status": ["type": summary.status],
		]
		json["name"] = summary.name
		json["preview"] = summary.preview
		json["updatedAt"] = summary.updatedAt?.timeIntervalSince1970
		return ThreadSummary(json: json)!
	}

	private func scopedDetail(
		_ detail: ThreadDetail,
		directory: URL
	) -> ThreadDetail
	{
		ThreadDetail(
			summary: scopedSummary(
				detail.summary,
				directory: directory
			),
			turns: detail.turns,
			nextTurnsCursor: detail.nextTurnsCursor
		)
	}

	func readThread(id: String) async throws -> ThreadDetail
	{
		let directory = fixtureDirectory
		readThreadCount += 1
		readThreadIDs.append(id)
		if let readThreadError
		{
			throw readThreadError
		}
		if suspendNextRead
		{
			suspendNextRead = false
			let detail: ThreadDetail = try await withCheckedThrowingContinuation
			{
				continuation in
				pendingRead = continuation
			}
			return scopedDetail(
				detail,
				directory: directory
			)
		}
		let summary: ThreadSummary
		if let otherThread, id == otherThread.id
		{
			summary = otherThread
		}
		else
		{
			summary = thread
		}
		return ThreadDetail(
			summary: scopedSummary(
				summary,
				directory: directory
			),
			turns: turnsByThreadID[id] ?? savedTurns,
			nextTurnsCursor: readNextCursor
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
		earlierReadCursors.append(cursor)
		if earlierReadsToSuspend > 0
		{
			earlierReadsToSuspend -= 1
			let requestNumber = earlierReadCursors.count
			return try await withCheckedThrowingContinuation
			{
				suspendedEarlierReads[requestNumber] = $0
			}
		}
		if suspendEarlierRead
		{
			return try await withCheckedThrowingContinuation
			{
				pendingEarlierRead = $0
			}
		}
		return earlierPages[cursor] ?? ([], nil)
	}

	func loadTurnReferences(
		threadId: String,
		cursor: String?
	) async throws -> TurnReferencePage
	{
		turnReferenceReads.append((threadId, cursor))
		if suspendTurnReferenceRead
		{
			return try await withCheckedThrowingContinuation
			{
				pendingTurnReferenceRead = $0
			}
		}
		return turnReferencePages[cursor ?? ""] ?? TurnReferencePage(
			references: [],
			nextCursor: nil
		)
	}

	func loadTurnContents(
		threadId: String,
		reference: ConversationTurnReference
	) async throws -> CodexTurn
	{
		turnContentReads.append((threadId, reference.id))
		if suspendTurnContentRead
		{
			return try await withCheckedThrowingContinuation
			{
				pendingTurnContentRead = $0
			}
		}
		guard let turn = referencedTurnContents[reference.id]
		else
		{
			throw AppServerError.requestRejected("The fixture has no content for this turn.")
		}
		return turn
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws -> CodexTurn
	{
		turnStartCount += 1
		if let startTurnError
		{
			throw startTurnError
		}
		if suspendTurnStart
		{
			return try await withCheckedThrowingContinuation
			{
				continuation in
				pendingTurnStart = continuation
			}
		}
		return nextTurn
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?,
		skills: [SkillReference]
	) async throws -> CodexTurn
	{
		sentTurnRequests.append((text, skills))
		return try await startTurn(
			threadId: threadId,
			text: text,
			model: model,
			effort: effort
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
		sentInputRequests.append(inputs)
		let text = textContent(in: inputs)
		return try await startTurn(
			threadId: threadId,
			text: text,
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
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences
	) async throws -> CodexTurn
	{
		capturedTurnPreferences.append((modelID: model, effort: effort, preferences: preferences))
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
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences,
		collaborationMode: CollaborationMode?,
		serviceTier: String?
	) async throws -> CodexTurn
	{
		guard collaborationMode == nil
		else
		{
			throw AppServerError
				.requestRejected("This Codex service cannot set collaboration mode.")
		}
		capturedTurnServiceTiers.append(serviceTier)
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

	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		interruptedTurnIDs.append(turnId)
		if suspendInterrupt
		{
			try await withCheckedThrowingContinuation
			{
				pendingInterrupt = $0
			}
		}
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		steeredTurns.append((threadId, expectedTurnId, text))
		if let steerError
		{
			throw steerError
		}
		if suspendSteer
		{
			return try await withCheckedThrowingContinuation
			{
				continuation in
				pendingSteer = continuation
			}
		}
		return steerAcknowledgedTurnID ?? expectedTurnId
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	{
		steeredInputRequests.append(inputs)
		let text = textContent(in: inputs)
		return try await steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			text: text
		)
	}

	private func textContent(in inputs: [TurnInput]) -> String
	{
		let textInputs = inputs.compactMap
		{
			input -> String? in
			if case .text(let text) = input
			{
				return text
			}
			return nil
		}
		return textInputs.joined(separator: "\n")
	}

	func finishPendingRead(with detail: ThreadDetail)
	{
		pendingRead?.resume(returning: detail)
		pendingRead = nil
	}

	func finishPendingRateLimitRead(with snapshot: AccountRateLimitsSnapshot)
	{
		pendingRateLimitRead?.resume(returning: snapshot)
		pendingRateLimitRead = nil
	}

	func finishPendingSteer(acknowledgedTurnID: String)
	{
		pendingSteer?.resume(returning: acknowledgedTurnID)
		pendingSteer = nil
	}

	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		respondedRequestIDs.append(requestID)
		beforeResponseReturns?()
		if let responseError
		{
			throw responseError
		}
	}

	func emit(_ event: AppServerEvent)
	{
		onEvent?(event)
	}

	func emitDisconnect(_ message: String)
	{
		onDisconnect?(message)
	}

	func finishTurnStart(with turn: CodexTurn)
	{
		pendingTurnStart?.resume(returning: turn)
		pendingTurnStart = nil
	}
}
