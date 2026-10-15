import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct GitReportedTurnRoutingTests
{
	@Test func missingReportsStayUnavailableRegardlessOfBaselineCaptureFailure()
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
		#expect(state.failure == .lastTurnUnavailable)
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
		#expect(state.failure == .lastTurnUnavailable)
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

	@Test func withdrawingReportsClearsThePreviousTurnsTotals() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "editing"
		)
		state.scope = .lastTurn
		let changes = [FileChange(json: [
			"path": "file.swift",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-old\n+new",
		])!]
		state.setReportedChanges(changes)
		let pendingRequest = state.beginRequest()
		let request = try #require(pendingRequest)
		let accepted = state.accept(
			GitReportedTurnComparison.compare(request),
			request: request
		)
		#expect(accepted)
		#expect(state.snapshot != nil)
		let transition = GitReviewReducer.reduce(
			state: &state,
			action: .setReportedChanges(nil),
			automaticRefreshEnabled: false
		)
		#expect(transition.publishes)
		#expect(state.snapshot == nil)
		#expect(state.failure == .lastTurnUnavailable)
		#expect(state.copyCommand == nil)
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
