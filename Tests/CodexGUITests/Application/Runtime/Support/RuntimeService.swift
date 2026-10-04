import Foundation
@testable import CodexGUI

@MainActor
final class RuntimeService: CodexService
{
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	var backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: nil,
		exitCode: nil,
		stderrTail: ""
	)
	var readIDs: [String] = []
	let turnStarted = RuntimeSignal()
	let responseStarted = RuntimeSignal()
	var responseDeliveryEvidence: Bool?
	var responseRequests: [String] = []
	var responseEvidenceQueries: [String] = []
	private var starts: [String: RuntimeSignal] = [:]
	private var returned: [String: RuntimeSignal] = [:]
	private var reads: [String: CheckedContinuation<ThreadDetail, Error>] = [:]
	private var turn: CheckedContinuation<CodexTurn, Error>?
	private var response: CheckedContinuation<Void, Never>?

	func readStarted(_ id: String) async
	{
		await signal(
			id,
			in: &starts
		).wait()
	}
	func readReturned(_ id: String) async
	{
		await signal(
			id,
			in: &returned
		).wait()
	}
	func completeRead(_ id: String)
	{
		reads.removeValue(forKey: id)?.resume(returning: detail(id))
	}
	func failRead(_ id: String)
	{
		reads.removeValue(forKey: id)?.resume(throwing: AppServerError.protocolError("read failed"))
	}
	func completeTurn()
	{
		turn?.resume(returning: CodexTurn(json: [
			"id": "turn",
			"status": "inProgress",
			"items": []
		])!)
		turn = nil
	}
	func completeResponse()
	{
		response?.resume()
		response = nil
	}
	private func signal(
		_ id: String,
		in signals: inout [String: RuntimeSignal]
	) -> RuntimeSignal
	{
		if let existing = signals[id]
		{
			return existing
		}
		let created = RuntimeSignal()
		signals[id] = created
		return created
	}
	private func detail(_ id: String) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": id, "cwd": "/tmp"])!,
			turns: [],
			nextTurnsCursor: nil
		)
	}
	func executableVersion() async throws -> String
	{
		"fixture"
	}
	func connect() async throws
	{
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
		URL(string: "https://example.com")!
	}
	func models() async throws -> [ModelOption]
	{
		[]
	}
	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		[]
	}
	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		detail("created")
	}
	func resumeThread(id: String) async throws -> ThreadDetail
	{
		detail(id)
	}
	func readThread(id: String) async throws -> ThreadDetail
	{
		readIDs.append(id)
		defer
		{
			signal(
				id,
				in: &returned
			).signal()
		}
		return try await withCheckedThrowingContinuation
		{
			continuation in
			reads[id] = continuation
			signal(
				id,
				in: &starts
			).signal()
		}
	}
	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws
		-> (turns: [CodexTurn], nextCursor: String?)
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
		try await withCheckedThrowingContinuation
		{
			continuation in
			turn = continuation
			turnStarted.signal()
		}
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
			text: "",
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
		expectedTurnId
	}
	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
	}
	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		responseRequests.append(requestID)
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
		await withCheckedContinuation
		{
			continuation in
			self.response = continuation
			responseStarted.signal()
		}
	}
	func responseMayHaveBeenSent(to requestID: String) -> Bool?
	{
		responseEvidenceQueries.append(requestID)
		return responseDeliveryEvidence
	}
}
