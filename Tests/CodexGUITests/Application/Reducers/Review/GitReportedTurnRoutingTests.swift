import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct GitReportedTurnRoutingTests
{
	@Test func unavailableRecordedPayloadUsesBaselineAndCompletedEmptyPayloadDoesNot() async
	{
		let baseline = ReportedTurnBaselineSpy()
		let service = LocalGitComparisonService(baselineService: baseline)
		let unavailable = GitComparisonRequest(
			owner: owner(),
			repositoryRoot: "/tmp/reported-git-turn",
			scope: .lastTurn,
			generation: 1,
			lastTurnID: "editing",
			reportedChanges: nil
		)
		let fallback = await service.compare(unavailable)
		#expect(fallback == .unavailable(.lastTurnUnavailable))
		#expect(await baseline.requestCount == 1)
		var empty = unavailable
		empty.reportedChanges = []
		let result = await service.compare(empty)
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Expected authoritative empty recorded comparison")
			return
		}
		#expect(snapshot.files.isEmpty)
		#expect(snapshot.patch.isEmpty)
		#expect(await baseline.requestCount == 1)
	}

	@Test func terminalBaselineFailureIsNotRetriedByRepeatedUnavailablePayloads()
	{
		var state = GitReviewState()
		let failure = GitComparisonFailure
			.lastTurnBaselineUnavailable("Captured files exceed the configured limit.")
		state.activate(
			owner: owner(),
			lastTurnID: "editing",
			baselineFailure: failure
		)
		state.scope = .lastTurn
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .setReportedChanges(nil),
			automaticRefreshEnabled: false
		)
		#expect(state.failure == failure)
		let generation = state.generation
		for _ in 0 ..< 3
		{
			let transition = GitReviewReducer.reduce(
				state: &state,
				action: .setReportedChanges(nil),
				automaticRefreshEnabled: false
			)
			#expect(transition.effects.isEmpty)
			#expect(!transition.publishes)
		}
		#expect(state.generation == generation)
		#expect(state.failure == failure)
	}

	@Test func contextChangesDiscardOldRecordedPatchesAndRejectTheirLateResults() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "old"
		)
		state.scope = .lastTurn
		state.setReportedChanges([])
		let oldOptional = state.beginRequest()
		let old = try #require(oldOptional)
		#expect(old.reportedChanges == [])
		let contextChanged = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 1
		)
		#expect(contextChanged)
		let currentOptional = state.beginRequest()
		let current = try #require(currentOptional)
		#expect(current.lastTurnID == "new")
		#expect(current.reportedChanges == nil)
		let acceptedOldRequest = state.accept(
			.unavailable(.lastTurnUnavailable),
			request: old
		)
		#expect(!acceptedOldRequest)
		#expect(state.pendingRequest == current)
	}

	private func owner() -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: "/tmp/reported-git-turn",
				threads: [],
				selectedThreadID: "thread",
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Test",
				backendDescription: "Test",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			),
			storeIdentity: "reported-git-turn-test"
		)
	}
}

private actor ReportedTurnBaselineSpy: GitTurnBaselineService
{
	private(set) var requestCount = 0

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		requestCount += 1
		return .unavailable(.lastTurnUnavailable)
	}

	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	{
		.unavailable(.lastTurnUnavailable)
	}

	func bind(
		_ reference: GitTurnBaselineReference,
		turnID: String
	) async -> GitTurnBaselineResult
	{
		.unavailable(.lastTurnUnavailable)
	}

	func lookup(
		repositoryRoot: String,
		threadID: String,
		turnID: String
	) async -> GitTurnBaselineReference?
	{
		nil
	}

	func discard(_ reference: GitTurnBaselineReference) async
	{
	}
}
