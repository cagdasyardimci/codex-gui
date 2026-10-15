import Foundation

@testable import CodexGUI

/// Suspends command acknowledgements independently of events and history reads.
@MainActor
final class ComposerCommandRuntimeService: CodexService
{
	let base = MockCodexService()
	private var pendingCallObservers: [UUID: @MainActor () -> Void] = [:]

	/// A checkpoint is reached after the service has installed the suspended acknowledgement.
	func awaitPendingCall(matching predicate: @escaping @MainActor () -> Bool) async -> Bool
	{
		let id = UUID()
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			pendingCallObservers[id] = check
			check()
		}
		for await _ in stream
		{
			break
		}
		pendingCallObservers.removeValue(forKey: id)
		return predicate()
	}

	private func pendingCallChanged()
	{
		for observer in Array(pendingCallObservers.values)
		{
			observer()
		}
	}
	var onEvent: ((AppServerEvent) -> Void)?
	{
		get
		{
			base.onEvent
		}
		set
		{
			base.onEvent = newValue
		}
	}
	var onDisconnect: ((String) -> Void)?
	{
		get
		{
			base.onDisconnect
		}
		set
		{
			base.onDisconnect = newValue
		}
	}
	var backendDiagnostics: BackendDiagnosticsSnapshot
	{
		base.backendDiagnostics
	}
	var pendingFork: CheckedContinuation<ThreadDetail, Error>?
	{
		didSet
		{
			pendingCallChanged()
		}
	}
	var pendingCompact: CheckedContinuation<Void, Error>?
	{
		didSet
		{
			pendingCallChanged()
		}
	}
	var pendingReview: CheckedContinuation<ReviewStartResult, Error>?
	{
		didSet
		{
			pendingCallChanged()
		}
	}
	var pendingSettings: CheckedContinuation<Void, Error>?
	{
		didSet
		{
			pendingCallChanged()
		}
	}
	var forkRequests: [(id: String, directory: URL?)] = []
	var compactRequests: [String] = []
	var reviewRequests: [(id: String, target: ReviewTarget, delivery: ReviewDelivery)] = []
	var settingsRequests: [(id: String, settings: ThreadSettingsUpdate)] = []
	var turnModes: [CollaborationMode?] = []
	var turnServiceTiers: [String?] = []

	func executableVersion() async throws -> String
	{
		try await base.executableVersion()
	}

	func connect() async throws
	{
		try await base.connect()
	}

	func disconnect()
	{
		base.disconnect()
	}

	func accountStatus() async throws -> AccountStatus
	{
		try await base.accountStatus()
	}

	func startBrowserLogin() async throws -> URL
	{
		try await base.startBrowserLogin()
	}

	func models() async throws -> [ModelOption]
	{
		try await base.models()
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		try await base
			.skills(for: directory)
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		try await base.rateLimits()
	}

	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		try await base
			.threads(for: directory)
	}

	func threads(
		for directory: URL,
		archived: Bool
	) async throws -> [ThreadSummary]
	{
		try await base.threads(
			for: directory,
			archived: archived
		)
	}

	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		try await base.startThread(
			in: directory,
			model: model
		)
	}

	func resumeThread(id: String) async throws -> ThreadDetail
	{
		try await base
			.resumeThread(id: id)
	}

	func resumeThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		try await base.resumeThread(
			id: id,
			expectedDirectory: expectedDirectory
		)
	}

	func readThread(id: String) async throws -> ThreadDetail
	{
		try await base.readThread(id: id)
	}

	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (turns: [CodexTurn], nextCursor: String?)
	{
		try await base.loadEarlierTurns(
			threadId: threadId,
			cursor: cursor
		)
	}

	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws -> CodexTurn
	{
		try await base.startTurn(
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
		turnModes.append(collaborationMode)
		turnServiceTiers.append(serviceTier)
		return try await base.startTurn(
			threadId: threadId,
			inputs: inputs,
			model: model,
			effort: effort,
			skills: skills,
			cwd: cwd,
			preferences: preferences
		)
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		try await base.steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			text: text
		)
	}

	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		inputs: [TurnInput]
	) async throws -> String
	{
		try await base.steerTurn(
			threadId: threadId,
			expectedTurnId: expectedTurnId,
			inputs: inputs
		)
	}

	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		try await base.interrupt(
			threadId: threadId,
			turnId: turnId
		)
	}

	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		try base.respond(
			to: requestID,
			with: response
		)
	}

	func forkThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		forkRequests.append((id, expectedDirectory))
		return try await withCheckedThrowingContinuation
		{
			pendingFork = $0
		}
	}

	func compactThread(id: String) async throws
	{
		compactRequests.append(id)
		try await withCheckedThrowingContinuation
		{
			pendingCompact = $0
		}
	}

	func startReview(
		threadId: String,
		target: ReviewTarget,
		delivery: ReviewDelivery
	) async throws -> ReviewStartResult
	{
		reviewRequests.append((threadId, target, delivery))
		return try await withCheckedThrowingContinuation
		{
			pendingReview = $0
		}
	}

	func updateThreadSettings(
		id: String,
		settings: ThreadSettingsUpdate
	) async throws
	{
		settingsRequests.append((id, settings))
		try await withCheckedThrowingContinuation
		{
			pendingSettings = $0
		}
	}

	func finishFork(_ detail: ThreadDetail)
	{
		base.otherThread = detail.summary
		base.turnsByThreadID[detail.summary.id] = detail.turns
		pendingFork?.resume(returning: detail)
		pendingFork = nil
	}

	func finishCompact()
	{
		pendingCompact?.resume()
		pendingCompact = nil
	}

	func finishReview(_ turn: CodexTurn)
	{
		pendingReview?.resume(returning: ReviewStartResult(
			reviewThreadId: base.thread.id,
			turn: turn
		))
		pendingReview = nil
	}

	func finishSettings()
	{
		pendingSettings?.resume()
		pendingSettings = nil
	}

	func failForkAfterDisconnect()
	{
		pendingFork?.resume(throwing: AppServerError.requestTimedOut("thread/fork"))
		pendingFork = nil
	}

	func failSettingsAfterDisconnect()
	{
		pendingSettings?.resume(throwing: AppServerError.requestTimedOut("thread/settings/update"))
		pendingSettings = nil
	}

	func rejectSettingsRetry()
	{
		pendingSettings?.resume(throwing: AppServerError.requestRejected("Fixture retry rejected"))
		pendingSettings = nil
	}

	func cancelPendingCalls()
	{
		let error = AppServerError.requestRejected("Runtime fixture closed")
		pendingFork?.resume(throwing: error)
		pendingFork = nil
		pendingCompact?.resume(throwing: error)
		pendingCompact = nil
		pendingReview?.resume(throwing: error)
		pendingReview = nil
		pendingSettings?.resume(throwing: error)
		pendingSettings = nil
		base.pendingTurnStart?.resume(throwing: error)
		base.pendingTurnStart = nil
		base.pendingRead?.resume(throwing: error)
		base.pendingRead = nil
		base.pendingSteer?.resume(throwing: error)
		base.pendingSteer = nil
	}
}
