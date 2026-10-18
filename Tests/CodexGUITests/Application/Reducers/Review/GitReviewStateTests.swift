import Foundation
import Testing

@testable import CodexGUI

struct GitReviewStateTests
{

	@Test func reducerKeepsPresentationChoicesOutOfComparisonReads() throws
	{
		var state = GitReviewState()
		let activation = GitReviewReducer.reduce(
			state: &state,
			action: .activate(
				owner: owner(),
				lastTurnID: nil,
				baselineRevision: 0,
				baselineFailure: nil
			),
			automaticRefreshEnabled: false
		)
		#expect(activation.publishes)
		let request = try #require(state.pendingRequest)
		let accepted = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(request)),
				request: request
			),
			automaticRefreshEnabled: false
		)
		#expect(accepted.publishes)
		let generation = state.generation
		let originalSummary = state.summary
		for action in [
			GitReviewAction.setFilter("no matches"),
			.expandGap("gap"),
			.toggleDirectory("src"),
			.selectFile("src/Example.swift")
		]
		{
			let transition = GitReviewReducer.reduce(
				state: &state,
				action: action,
				automaticRefreshEnabled: false
			)
			#expect(transition.publishes)
			#expect(transition.effects.isEmpty)
		}
		#expect(state.generation == generation)
		#expect(state.summary == originalSummary)
		#expect(state.pendingRequest == nil)
	}

	@Test func reducerRejectsLateReadAfterScopeChangeAndClose() throws
	{
		var state = GitReviewState()
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .activate(
				owner: owner(),
				lastTurnID: nil,
				baselineRevision: 0,
				baselineFailure: nil
			),
			automaticRefreshEnabled: false
		)
		let old = try #require(state.pendingRequest)
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .selectScope(.staged),
			automaticRefreshEnabled: false
		)
		let staged = try #require(state.pendingRequest)
		let late = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(old)),
				request: old
			),
			automaticRefreshEnabled: false
		)
		#expect(!late.publishes)
		#expect(state.pendingRequest == staged)
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .close,
			automaticRefreshEnabled: false
		)
		let closed = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(staged)),
				request: staged
			),
			automaticRefreshEnabled: false
		)
		#expect(!closed.publishes)
		#expect(state.snapshot == nil)
	}

	@Test func ownerScopeGenerationAndCloseRejectLateResults() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		state.scope = .staged
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedRetiredRequest = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(!acceptedRetiredRequest)
		let acceptedCurrentRequest = state.accept(
			.snapshot(snapshot(second)),
			request: second
		)
		#expect(acceptedCurrentRequest)
		state.activate(owner: owner("another"))
		let acceptedForeignOwnerRequest = state.accept(
			.snapshot(snapshot(second)),
			request: second
		)
		#expect(!acceptedForeignOwnerRequest)
		let thirdOptional = state.beginRequest()
		let third = try #require(thirdOptional)
		state.close()
		let acceptedClosedRequest = state.accept(
			.snapshot(snapshot(third)),
			request: third
		)
		#expect(!acceptedClosedRequest)
		#expect(state.snapshot == nil)
	}

	@Test func reopenedSameOwnerRejectsPreviousLifetime() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let oldOptional = state.beginRequest()
		let old = try #require(oldOptional)
		state.close()
		state.activate(owner: owner())
		let currentOptional = state.beginRequest()
		let current = try #require(currentOptional)
		#expect(old.generation < current.generation)
		let acceptedPreviousLifetime = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(!acceptedPreviousLifetime)
		#expect(state.pendingRequest == current)
	}

	@Test func filtersKeepRawSummaryAndStaleCopiesAreDisabled() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let requestOptional = state.beginRequest()
		let request = try #require(requestOptional)
		let acceptedInitialSnapshot = state.accept(
			.snapshot(snapshot(request)),
			request: request
		)
		#expect(acceptedInitialSnapshot)
		state.filter = "no matches"
		state.options.ignoreImports = true
		#expect(state.summary == .available(SummaryChangeTotals(
			additions: 1,
			deletions: 1
		)))
		#expect(state.copyCommand != nil)
		let replacementOptional = state.beginRequest()
		let replacement = try #require(replacementOptional)
		#expect(state.isStale)
		#expect(state.copyCommand == nil)
		let acceptedReplacementFailure = state.accept(
			.unavailable(.repositoryChanged),
			request: replacement
		)
		#expect(acceptedReplacementFailure)
		#expect(state.snapshot != nil)
		#expect(state.copyCommand == nil)
	}

	@Test func unchangedRefreshPreservesSnapshotContextIdentity() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		let acceptedFirstSnapshot = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(acceptedFirstSnapshot)
		state.options.expandedGapIDs = [Data("gap".utf8)]
		state.expandedDirectories.removeAll()
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedUnchangedSnapshot = state.accept(
			.snapshot(snapshot(
				second,
				id: "new"
			)),
			request: second
		)
		#expect(acceptedUnchangedSnapshot)
		#expect(state.snapshot?.id == "snapshot")
		#expect(state.options.expandedGapIDs == [Data("gap".utf8)])
		#expect(state.expandedDirectories.isEmpty)
	}

	@Test func mismatchedSnapshotDoesNotConsumePendingRequest() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedMismatchedSnapshot = state.accept(
			.snapshot(snapshot(first)),
			request: second
		)
		#expect(!acceptedMismatchedSnapshot)
		#expect(state.pendingRequest == second)
	}

	@Test func reportedFallbackSurvivesAcceptanceAndChangesComparisonIdentity() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		state.scope = .lastTurn
		let firstRequest = state.beginRequest()
		let first = try #require(firstRequest)
		let acceptedFirst = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(acceptedFirst)
		#expect(state.copyCommand != nil)
		state.options.expandedGapIDs = [Data("gap".utf8)]
		let secondRequest = state.beginRequest()
		let second = try #require(secondRequest)
		var fallback = snapshot(
			second,
			id: "fallback"
		)
		fallback.usesReportedEditFallback = true
		let acceptedFallback = state.accept(
			.snapshot(fallback),
			request: second
		)
		#expect(acceptedFallback)
		#expect(state.snapshot?.usesReportedEditFallback == true)
		#expect(state.snapshot?.id == "fallback")
		#expect(state.options.expandedGapIDs.isEmpty)
		#expect(state.copyCommand == nil)
		let thirdRequest = state.beginRequest()
		let third = try #require(thirdRequest)
		let acceptedApplicable = state.accept(
			.snapshot(snapshot(
				third,
				id: "applicable"
			)),
			request: third
		)
		#expect(acceptedApplicable)
		#expect(state.snapshot?.usesReportedEditFallback == false)
		#expect(state.snapshot?.id == "applicable")
		#expect(state.copyCommand != nil)
	}

	@Test func latestTurnAndCapturePublicationInvalidateOnlyLastTurnRequests() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "old",
			baselineRevision: 1
		)
		state.scope = .lastTurn
		let oldOptional = state.beginRequest()
		let old = try #require(oldOptional)
		#expect(old.lastTurnID == "old")
		let turnContextResult1 = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(turnContextResult1)
		let turnContextResult2 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 1
		)
		#expect(turnContextResult2)
		#expect(state.snapshot == nil)
		#expect(!state.isStale)
		#expect(state.copyCommand == nil)
		let currentOptional = state.beginRequest()
		let current = try #require(currentOptional)
		#expect(current.lastTurnID == "new")
		let turnContextResult3 = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(!turnContextResult3)
		let turnContextResult4 = state.accept(
			.unavailable(.lastTurnUnavailable),
			request: current
		)
		#expect(turnContextResult4)
		#expect(state.snapshot == nil)
		#expect(state.summary == .failed(
			GitComparisonFailure.lastTurnUnavailable.message,
			previous: nil
		))
		let failedGeneration = state.generation
		let turnContextResult5 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 1
		)
		#expect(!turnContextResult5)
		#expect(state.generation == failedGeneration)
		let turnContextResult6 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 2
		)
		#expect(turnContextResult6)
		let afterBindingOptional = state.beginRequest()
		let afterBinding = try #require(afterBindingOptional)
		#expect(afterBinding.lastTurnID == "new")
		#expect(afterBinding.generation > failedGeneration)
		state.scope = .uncommitted
		let uncommittedOptional = state.beginRequest()
		let uncommitted = try #require(uncommittedOptional)
		#expect(uncommitted.lastTurnID == nil)
		let turnContextResult7 = state.updateTurnContext(
			lastTurnID: "later",
			baselineRevision: 3
		)
		#expect(!turnContextResult7)
		#expect(state.pendingRequest == uncommitted)
	}

	@Test func latestTurnContextResetsOnOwnerChangeAndClose() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "first-turn",
			baselineRevision: 4
		)
		state.scope = .lastTurn
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		state.activate(
			owner: owner("another"),
			lastTurnID: "other-turn",
			baselineRevision: 1
		)
		state.scope = .lastTurn
		let otherOptional = state.beginRequest()
		let other = try #require(otherOptional)
		#expect(other.lastTurnID == "other-turn")
		let turnContextResult8 = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(!turnContextResult8)
		state.close()
		#expect(state.lastTurnID == nil)
		#expect(state.baselineRevision == 0)
	}

	@Test func literalFileAndDirectoryIdentitiesStayIndependentAcrossRefreshes() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let composed = "Café/A.swift"
		let decomposed = "Cafe\u{301}/A.swift"
		let firstRequest = state.beginRequest()
		let first = try #require(firstRequest)
		let acceptedFirst = state.accept(
			.snapshot(snapshot(
				first,
				paths: [composed, decomposed]
			)),
			request: first
		)
		#expect(acceptedFirst)
		#expect(state.expandedDirectories == [Data("Café".utf8), Data("Cafe\u{301}".utf8)])
		state.toggleDirectory("Café")
		#expect(state.expandedDirectories == [Data("Cafe\u{301}".utf8)])
		state.expandGap("snapshot:Café/A.swift:gap")
		state.expandGap("snapshot:Cafe\u{301}/A.swift:gap")
		#expect(state.options.expandedGapIDs.count == 2)
		let selectedDecomposed = state.selectFile(decomposed)
		#expect(selectedDecomposed)
		let secondRequest = state.beginRequest()
		let second = try #require(secondRequest)
		let acceptedSecond = state.accept(
			.snapshot(snapshot(
				second,
				paths: [composed]
			)),
			request: second
		)
		#expect(acceptedSecond)
		#expect(state.selectedFileID?.utf8.elementsEqual(composed.utf8) == true)
		#expect(state.selectionMessage == "The selected file is absent from the new comparison.")
		let selectedMissing = state.selectFile(decomposed)
		#expect(!selectedMissing)
	}

	@Test func reportedChangeInvalidationKeepsExactBytesAndOptionalAvailability() throws
	{
		var state = GitReviewState()
		let changedMissing = state.setReportedChanges(nil)
		#expect(!changedMissing)
		let changedToEmpty = state.setReportedChanges([])
		#expect(changedToEmpty)
		let changedEmpty = state.setReportedChanges([])
		#expect(!changedEmpty)
		let changedToMissing = state.setReportedChanges(nil)
		#expect(changedToMissing)
		let composed = try #require(FileChange(json: [
			"path": "A.swift",
			"kind": "update",
			"diff": "-before\n+é\n",
		]))
		let decomposed = try #require(FileChange(json: [
			"path": "A.swift",
			"kind": "update",
			"diff": "-before\n+e\u{301}\n",
		]))
		#expect(composed == decomposed)
		let changedToComposed = state.setReportedChanges([composed])
		#expect(changedToComposed)
		let changedComposed = state.setReportedChanges([composed])
		#expect(!changedComposed)
		let changedToDecomposed = state.setReportedChanges([decomposed])
		#expect(changedToDecomposed)
		#expect(state.reportedChanges?.first?.diff.utf8.elementsEqual(decomposed.diff.utf8) == true)
	}

	private func snapshot(
		_ request: GitComparisonRequest,
		id: String = "snapshot",
		paths: [String] = ["src/Example.swift"]
	)
		-> GitComparisonSnapshot
	{
		let bytes = Data("diff --git a/src/Example.swift b/src/Example.swift\n".utf8)
		return GitComparisonSnapshot(
			request: request,
			id: id,
			resolvedBase: "base",
			resolvedTarget: "target",
			patch: bytes,
			files: paths.map
			{
				GitComparisonFile(
					oldPath: $0,
					newPath: $0,
					kind: .modified,
					additions: 1,
					deletions: 1,
					isBinary: false,
					patch: "",
					hunks: []
				)
			}
		)
	}

	private func owner(_ thread: String = "thread") -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: "/neutral",
				threads: [],
				selectedThreadID: thread,
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
			storeIdentity: "test"
		)
	}
}
