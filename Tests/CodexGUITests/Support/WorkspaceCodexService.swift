import Foundation

@testable import CodexGUI

@MainActor
final class WorkspaceCodexService: CodexService
{
	struct TurnIdentity: Equatable
	{
		let threadID: String
		let turnID: String
	}

	struct TurnRequest
	{
		let threadID: String
		let inputs: [TurnInput]
		let cwd: URL?
	}

	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	var backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: "codex-cli 0.153.2",
		exitCode: nil,
		stderrTail: ""
	)
	let threadID: String
	var reportedDirectory: URL
	var thread: ThreadSummary
	{
		ThreadSummary(json: ["id": threadID, "cwd": reportedDirectory.path])!
	}
	let turn = CodexTurn(json: ["id": "turn-one", "status": "inProgress", "items": []])!
	var savedTurns: [CodexTurn] = []
	var additionalThreads: [String: ThreadDetail] = [:]
	/// List snapshots can lag the authoritative detail returned by read or resume.
	var readThreadDetails: [String: ThreadDetail] = [:]
	var readThreadIDs: [String] = []
	var accountReadCount = 0
	var modelReadCount = 0
	var skillReadCount = 0
	var rateLimitReadCount = 0
	var readThreadCount = 0
	var turnRequests: [TurnRequest] = []
	var observeTurnStart: ((String) -> Void)?
	var respondedRequestIDs: [String] = []
	var interruptionRequests: [TurnIdentity] = []
	var interruptError: Error?
	var steeringRequests: [TurnIdentity] = []
	var disconnectCount = 0
	var connectionCount = 0
	var suspendConnection = false
	var pendingConnection: CheckedContinuation<Void, Error>?
	var suspendThreadStart = false
	var pendingThreadStart: CheckedContinuation<ThreadDetail, Error>?
	private var checkpoints: Set<String> = []
	private var checkpointWaiters: [String: [UUID: AsyncStream<Void>.Continuation]] = [:]

	func waitForCheckpoint(_ checkpoint: String) async
	{
		guard !checkpoints.contains(checkpoint)
		else
		{
			return
		}
		let id = UUID()
		let stream = AsyncStream<Void>
		{
			checkpointWaiters[checkpoint, default: [:]][id] = $0
		}
		defer
		{
			checkpointWaiters[checkpoint]?.removeValue(forKey: id)
			if checkpointWaiters[checkpoint]?.isEmpty == true
			{
				checkpointWaiters.removeValue(forKey: checkpoint)
			}
		}
		// A test time limit cancels stream iteration rather than leaving a parked continuation.
		for await _ in stream
		{
			break
		}
	}

	private func reached(_ checkpoint: String)
	{
		checkpoints.insert(checkpoint)
		for waiter in checkpointWaiters.removeValue(forKey: checkpoint)?.values ?? [:].values
		{
			waiter.yield(())
			waiter.finish()
		}
	}

	var suspendTurnStart = false
	var pendingTurnStart: CheckedContinuation<CodexTurn, Error>?
	var suspendSteer = false
	var pendingSteer: CheckedContinuation<String, Error>?
	var suspendNextRead = false
	var pendingRead: CheckedContinuation<ThreadDetail, Error>?

	init(
		directory: URL,
		threadID: String
	)
	{
		reportedDirectory = directory
		self.threadID = threadID
	}

	func executableVersion() async throws -> String
	{
		"codex-cli 0.153.2"
	}

	func connect() async throws
	{
		connectionCount += 1
		reached("connect:\(connectionCount)")
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
		disconnectCount += 1
	}

	func accountStatus() async throws -> AccountStatus
	{
		accountReadCount += 1
		return AccountStatus(
			type: "chatgpt",
			email: nil,
			requiresOpenAIAuth: false
		)
	}

	func startBrowserLogin() async throws -> URL
	{
		URL(string: "https://example.test")!
	}

	func models() async throws -> [ModelOption]
	{
		modelReadCount += 1
		return []
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		skillReadCount += 1
		return SkillCatalog(
			skills: [],
			errors: []
		)
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		rateLimitReadCount += 1
		return AccountRateLimitsSnapshot(json: ["rateLimits": ["primary": ["usedPercent": 0.0]]])!
	}

	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		[thread] + additionalThreads.values.map(\.summary)
	}

	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		reached("threadStart")
		if suspendThreadStart
		{
			return try await withCheckedThrowingContinuation
			{
				pendingThreadStart = $0
			}
		}
		return detail()
	}

	func resumeThread(id: String) async throws -> ThreadDetail
	{
		readThreadDetails[id] ?? additionalThreads[id] ?? detail()
	}

	func readThread(id: String) async throws -> ThreadDetail
	{
		readThreadCount += 1
		readThreadIDs.append(id)
		if suspendNextRead
		{
			suspendNextRead = false
			return try await withCheckedThrowingContinuation
			{
				pendingRead = $0
				reached("read:\(readThreadCount)")
			}
		}
		reached("read:\(readThreadCount)")
		return readThreadDetails[id] ?? additionalThreads[id] ?? detail()
	}

	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (
		turns: [CodexTurn],
		nextCursor: String?
	)
	{
		([], nil)
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws
		-> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			inputs: [.text(text)],
			model: model,
			effort: effort,
			skills: [],
			cwd: nil
		)
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
		observeTurnStart?(threadId)
		turnRequests.append(TurnRequest(
			threadID: threadId,
			inputs: inputs,
			cwd: cwd
		))
		reached("turnStart:\(turnRequests.count)")
		if suspendTurnStart
		{
			return try await withCheckedThrowingContinuation
			{
				pendingTurnStart = $0
			}
		}
		return turn
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		steeringRequests.append(TurnIdentity(
			threadID: threadId,
			turnID: expectedTurnId
		))
		if suspendSteer
		{
			return try await withCheckedThrowingContinuation
			{
				pendingSteer = $0
				reached("steer:\(steeringRequests.count)")
			}
		}
		reached("steer:\(steeringRequests.count)")
		return expectedTurnId
	}

	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		interruptionRequests.append(TurnIdentity(
			threadID: threadId,
			turnID: turnId
		))
		reached("interrupt:\(interruptionRequests.count)")
		if let interruptError
		{
			throw interruptError
		}
	}

	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		respondedRequestIDs.append(requestID)
	}

	func emit(_ event: AppServerEvent)
	{
		onEvent?(event)
	}

	func detail() -> ThreadDetail
	{
		ThreadDetail(
			summary: thread,
			turns: savedTurns,
			nextTurnsCursor: nil
		)
	}

	func finishedTurn(status: String) -> CodexTurn
	{
		CodexTurn(json: ["id": turn.id, "status": status, "items": []])!
	}

	func complete(
		threadID: String,
		status: String
	)
	{
		let completed = finishedTurn(status: status)
		if let detail = readThreadDetails[threadID]
		{
			readThreadDetails[threadID] = ThreadDetail(
				summary: ThreadSummary(json: [
					"id": threadID,
					"cwd": detail.summary.cwd,
					"status": ["type": "idle"],
				])!,
				turns: [completed],
				nextTurnsCursor: nil
			)
		}
		if let detail = additionalThreads[threadID]
		{
			additionalThreads[threadID] = ThreadDetail(
				summary: detail.summary,
				turns: [completed],
				nextTurnsCursor: nil
			)
		}
		else
		{
			savedTurns = [completed]
		}
		emit(.turnCompleted(
			threadId: threadID,
			turn: completed
		))
	}

	func complete(status: String)
	{
		let completed = finishedTurn(status: status)
		savedTurns = [completed]
		emit(.turnCompleted(
			threadId: thread.id,
			turn: completed
		))
	}

	func approval(id: String) -> PendingInteraction
	{
		PendingInteraction(
			id: id,
			threadId: thread.id,
			turnId: turn.id,
			itemId: "command",
			approvalId: nil,
			kind: .commandApproval,
			reason: nil,
			command: "check",
			cwd: reportedDirectory.path,
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: nil,
			additionalPermissions: nil,
			availableDecisions: [.accept, .decline]
		)
	}
}
