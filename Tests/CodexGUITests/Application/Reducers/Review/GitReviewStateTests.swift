import Foundation
import Testing

@testable import CodexGUI

struct GitReviewStateTests
{

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

	@Test func fileSelectionAndReportedChangesRetainExactPathBytes() throws
	{
		let composed = "\u{00E9}"
		let decomposed = "e\u{0301}"
		var state = GitReviewState()
		state.activate(owner: owner())
		let pending = state.beginRequest()
		let request = try #require(pending)
		let patch = Data(("diff --git a/\(composed)/file b/\(composed)/file\n"
				+ "--- a/\(composed)/file\n+++ b/\(composed)/file\n@@ -1 +1 @@\n-a\n+b\n").utf8)
		let value = GitComparisonSnapshot(
			request: request,
			id: "unicode",
			resolvedBase: "base",
			resolvedTarget: "target",
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch)
		)
		let accepted = state.accept(
			.snapshot(value),
			request: request
		)
		#expect(accepted)
		let selectedEquivalentSpelling = state.selectFile(decomposed + "/file")
		#expect(!selectedEquivalentSpelling)
		let selectedExactSpelling = state.selectFile(composed + "/file")
		#expect(selectedExactSpelling)
		let first = FileChange(json: ["path": composed, "diff": ""])!
		let second = FileChange(json: ["path": decomposed, "diff": ""])!
		let acceptedFirstReports = state.setReportedChanges([first])
		#expect(acceptedFirstReports)
		let acceptedByteDistinctReports = state.setReportedChanges([second])
		#expect(acceptedByteDistinctReports)
		let repeatedReports = state.setReportedChanges([second])
		#expect(!repeatedReports)
		let retainedReports = try #require(state.reportedChanges)
		#expect(retainedReports.count == 1)
		#expect(retainedReports.first?.path.utf8.elementsEqual(decomposed.utf8) == true)
		let clearedReports = state.setReportedChanges(nil)
		#expect(clearedReports)
		#expect(state.reportedChanges == nil)
		let repeatedMissingReports = state.setReportedChanges(nil)
		#expect(!repeatedMissingReports)
		let emptyReports = state.setReportedChanges([])
		#expect(emptyReports)
		#expect(state.reportedChanges?.isEmpty == true)
		let repeatedEmptyReports = state.setReportedChanges([])
		#expect(!repeatedEmptyReports)
	}

	private func snapshot(
		_ request: GitComparisonRequest,
		id: String = "snapshot"
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
			files: [GitComparisonFile(
				oldPath: "src/Example.swift",
				newPath: "src/Example.swift",
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: "",
				hunks: []
			)]
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
