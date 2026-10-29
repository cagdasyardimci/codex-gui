import Foundation

@testable import CodexGUI

/// One transport hosts ordinary conversations in the same checkout.
@MainActor
final class ConcurrentChatService: CodexService
{
	struct TurnRequest
	{
		let threadID: String
		let turnID: String
		let text: String
	}

	let processIdentity = UUID()
	let checkout: URL
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	let backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: "codex-cli 0.153.2",
		exitCode: nil,
		stderrTail: ""
	)
	private(set) var connectionCount = 0
	private(set) var starts: [TurnRequest] = []
	private(set) var submittedPreferences: [RunPreferences] = []
	private(set) var steering: [TurnRequest] = []
	private(set) var interruptions: [TurnRequest] = []
	private(set) var responses: [String] = []
	private(set) var reads: [String] = []
	private(set) var resumeDirectories: [(threadID: String, directory: URL?)] = []
	var turns: [String: [CodexTurn]] = [:]
	var resumeOverrides: [String: ThreadDetail] = [:]
	var suspendedResumes: Set<String> = []
	var suspendedSteering: Set<String> = []
	private var pendingResumes: [String: CheckedContinuation<ThreadDetail, Error>] = [:]
	private var pendingSteering: [String: CheckedContinuation<String, Error>] = [:]
	private var signals: [String: RuntimeSignal] = [:]

	init(checkout: URL)
	{
		self.checkout = checkout
	}

	func waitForResume(_ threadID: String) async
	{
		await signal("resume:\(threadID)").wait()
	}

	func waitForSteering(_ threadID: String) async
	{
		await signal("steer:\(threadID)").wait()
	}

	func finishResume(_ threadID: String)
	{
		pendingResumes.removeValue(forKey: threadID)?.resume(returning: detail(threadID))
	}

	func finishSteering(_ threadID: String)
	{
		let turnID = steering.last(where:
			{
				$0.threadID == threadID
			})!.turnID
		pendingSteering.removeValue(forKey: threadID)?.resume(returning: turnID)
	}

	func releaseSuspendedOperations()
	{
		for threadID in Array(pendingResumes.keys)
		{
			finishResume(threadID)
		}
		for threadID in Array(pendingSteering.keys)
		{
			finishSteering(threadID)
		}
	}

	private func signal(_ key: String) -> RuntimeSignal
	{
		if let existing = signals[key]
		{
			return existing
		}
		let created = RuntimeSignal()
		signals[key] = created
		return created
	}

	func summary(_ threadID: String) -> ThreadSummary
	{
		let status = turns[threadID]?.last?.status == "inProgress" ? "active" : "idle"
		return ThreadSummary(json: [
			"id": threadID,
			"name": threadID,
			"preview": threadID,
			"cwd": checkout.path,
			"status": ["type": status],
		])!
	}

	func detail(_ threadID: String) -> ThreadDetail
	{
		ThreadDetail(
			summary: summary(threadID),
			turns: turns[threadID] ?? [],
			nextTurnsCursor: nil
		)
	}

	static func turn(
		_ turnID: String,
		status: String = "inProgress",
		text: String? = nil
	) -> CodexTurn
	{
		let items: [[String: Any]] = text.map
		{
			[["id": "answer", "type": "agentMessage", "text": $0]]
		} ?? []
		return CodexTurn(json: ["id": turnID, "status": status, "items": items])!
	}

	func emit(_ event: AppServerEvent)
	{
		onEvent?(event)
	}

	func executableVersion() async throws -> String
	{
		"codex-cli 0.153.2"
	}

	func connect() async throws
	{
		connectionCount += 1
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
		[]
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		SkillCatalog(
			skills: [],
			errors: []
		)
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		AccountRateLimitsSnapshot(json: [
			"rateLimits": ["primary": ["usedPercent": 20.0]]
		])!
	}

	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		[summary("chat-a"), summary("chat-b")]
	}

	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		if archived
		{
			return []
		}
		return try await threads(for: directory)
	}

	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		detail("created-chat")
	}

	func resumeThread(id: String) async throws -> ThreadDetail
	{
		if let override = resumeOverrides[id]
		{
			return override
		}
		if suspendedResumes.contains(id)
		{
			return try await withCheckedThrowingContinuation
			{
				pendingResumes[id] = $0
				signal("resume:\(id)").signal()
			}
		}
		return detail(id)
	}

	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		resumeDirectories.append((id, expectedDirectory))
		// Deliberate bad responses exercise the runner's independent ownership validation.
		return try await resumeThread(id: id)
	}

	func readThread(id: String) async throws -> ThreadDetail
	{
		reads.append(id)
		return detail(id)
	}

	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (turns: [CodexTurn], nextCursor: String?)
	{
		([], nil)
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws -> CodexTurn
	{
		let turnID = "\(threadId)-turn-\(starts.filter { $0.threadID == threadId }.count + 1)"
		starts.append(TurnRequest(
			threadID: threadId,
			turnID: turnID,
			text: text
		))
		let created = Self.turn(turnID)
		turns[threadId, default: []].append(created)
		return created
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
		submittedPreferences.append(preferences)
		return try await startTurn(
			threadId: threadId,
			text: text(in: inputs),
			model: model,
			effort: effort
		)
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		steering.append(TurnRequest(
			threadID: threadId,
			turnID: expectedTurnId,
			text: text
		))
		if suspendedSteering.contains(threadId)
		{
			return try await withCheckedThrowingContinuation
			{
				pendingSteering[threadId] = $0
				signal("steer:\(threadId)").signal()
			}
		}
		signal("steer:\(threadId)").signal()
		return expectedTurnId
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	{
		try await steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			text: text(in: inputs)
		)
	}

	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		interruptions.append(TurnRequest(
			threadID: threadId,
			turnID: turnId,
			text: ""
		))
	}

	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		responses.append(requestID)
	}

	private func text(in inputs: [TurnInput]) -> String
	{
		inputs.compactMap
		{
			if case .text(let value) = $0
			{
				return value
			}
			return nil
		}.joined(separator: "\n")
	}
}
