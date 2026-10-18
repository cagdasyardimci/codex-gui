import Foundation
import Testing

@testable import CodexGUI

struct ConversationTurnChangeSummaryTests
{
	@Test func reportedItemsExcludeAggregateDiffAndEarlierTurns() throws
	{
		let diff = "diff --git a/OtherTask.swift b/OtherTask.swift\n"
			+ "--- a/OtherTask.swift\n+++ b/OtherTask.swift\n"
			+ "@@ -1 +1 @@\n-other task before\n+other task after\n"
		for aggregate in [diff, ""]
		{
			let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot(
				activeTurnDiff: aggregate
			)
			let summary = try #require(ConversationTurnChangeSummary(snapshot))
			#expect(summary.failure == nil)
			#expect(summary.fileCount == 2)
			#expect(summary.additions == 3)
			#expect(summary.deletions == 1)
			let request = try #require(snapshot.runningGitReviewRequest(
				owner: FeaturePresentationOwner(snapshot)
			))
			guard case .snapshot(let comparison) = GitReportedTurnComparison.compare(request)
			else
			{
				Issue.record("Expected the same recorded comparison as the badge")
				return
			}
			#expect(ConversationTurnChangeSummary(comparison: comparison) == summary)
			#expect(comparison.files.map(\.path) == ["Sources/First.swift", "Sources/Second.swift"])
		}
	}

	@Test @MainActor func missingActiveReportsUsePreviousTurnOnlyForTheBadge() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot(reports: false)
		snapshot.reportedGitTurnID = "previous"
		snapshot.reportedGitChanges = [change("@@ -1 +1 @@\n-old\n+new")]
		snapshot.activeTurnDiff = "diff --git a/Other.swift b/Other.swift\n@@ -0,0 +1 @@\n+other"
		#expect(snapshot.visibleGitReviewTurn.id == "turn")
		#expect(snapshot.visibleGitReviewTurn.changes == nil)
		let summary = try #require(ConversationTurnChangeSummary(snapshot))
		#expect(summary.failure == nil)
		#expect(summary.usesPreviousTurn)
		#expect(summary.additions == 1)
		#expect(summary.deletions == 1)
		snapshot.reportedGitChanges = nil
		#expect(ConversationTurnChangeSummary(snapshot)?.failure == .lastTurnUnavailable)
		snapshot.activeThreadID = "another-task"
		#expect(ConversationTurnChangeSummary(snapshot) == nil)
	}

	@Test func repeatedEditsUseNetCountsAndReversalsProduceNoBadge() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		let first = change("@@ -1 +1 @@\n-before\n+intermediate")
		snapshot.reportedGitChanges = [first, change("@@ -1 +1 @@\n-intermediate\n+after")]
		let summary = try #require(ConversationTurnChangeSummary(snapshot))
		#expect(summary.fileCount == 1)
		#expect(summary.additions == 1)
		#expect(summary.deletions == 1)
		#expect(!summary.usesReportedEditFallback)
		snapshot.reportedGitChanges = [first, change("@@ -1 +1 @@\n-intermediate\n+before")]
		#expect(ConversationTurnChangeSummary(snapshot) == nil)
		snapshot.reportedGitChanges = []
		#expect(ConversationTurnChangeSummary(snapshot) == nil)
	}

	@Test @MainActor func interleavedSameFileEditsFallBackToReportedCounts() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		snapshot.reportedGitChanges = [
			change("@@ -1 +1 @@\n-before\n+task A"),
			change("@@ -1 +1 @@\n-task B\n+task A again"),
		]
		let summary = try #require(ConversationTurnChangeSummary(snapshot))
		#expect(summary.failure == nil)
		#expect(summary.usesReportedEditFallback)
		#expect(summary.fileCount == 1)
		#expect(summary.additions == 2)
		#expect(summary.deletions == 2)
	}

	@Test(arguments: [GitComparisonFailure.lastTurnUnavailable,
						.oversized,
						.repositoryUnavailable,
						.cancelled,
						.failed("Preview failed")])
	@MainActor func failuresDisplayCountsWithoutUnavailableText(
		_ failure: GitComparisonFailure
	) throws
	{
		let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		let request = try #require(snapshot.runningGitReviewRequest(
			owner: FeaturePresentationOwner(snapshot)
		))
		let summary = try #require(ConversationTurnChangeSummary(
			result: .unavailable(failure),
			request: request
		))
		#expect(summary.fileCount == 2)
		#expect(summary.additions == 3)
		#expect(summary.deletions == 1)
		let unavailable = ConversationTurnChangeSummary(unavailable: failure)
		#expect(unavailable.fileCount == 0)
		#expect(unavailable.additions == 0)
		#expect(unavailable.deletions == 0)
	}

	@Test func unavailableComparisonCountsLargeReportsAndNormalizedWholeFileChanges() throws
	{
		let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		var request = try #require(snapshot.runningGitReviewRequest(
			owner: FeaturePresentationOwner(snapshot)
		))
		let repeatedEdits = String(
			repeating: "-before\n+after\n context\n",
			count: 2_000
		)
		request.reportedChanges = [
			change("@@ -1,4000 +1,4000 @@\n" + repeatedEdits),
			change("@@ malformed\n+counted\ndiff --git a/other b/other\n+outside hunk"),
			try #require(FileChange(json: [
				"path": "added.swift",
				"kind": "add",
				"diff": "first\nsecond\n",
			])),
			try #require(FileChange(json: [
				"path": "deleted.swift",
				"kind": "delete",
				"diff": "removed\n",
			])),
		]
		let summary = ConversationTurnChangeSummary(
			unavailable: .oversized,
			request: request
		)
		#expect(summary.fileCount == 3)
		#expect(summary.additions == 2_003)
		#expect(summary.deletions == 2_001)
		#expect(summary.failure == .oversized)
		#expect(summary.usesReportedEditFallback)
	}

	private func change(_ diff: String) -> FileChange
	{
		FileChange(json: ["path": "same.swift", "kind": "update", "diff": diff])!
	}
}
