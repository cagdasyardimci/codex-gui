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
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "1 file changed +1 -1")
		#expect(button.toolTip?.contains("Previous editing turn") == true)
		#expect(button.accessibilityLabel()?.contains("Previous editing turn") == true)
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
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "1 file changed +2 -2")
		#expect(button.toolTip?.contains(GitReportedTurnComparison.fallbackMessage) == true)
		#expect(button.accessibilityLabel()?.contains("These are not net changes.") == true)
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
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "2 files changed +3 -1")
		#expect(button.toolTip?.contains(failure.message) == false)
		#expect(button.accessibilityLabel()?.contains(failure.message) == false)
		button.render(ConversationTurnChangeSummary(unavailable: failure))
		#expect(button.attributedTitle.string == "0 files changed +0 -0")
		#expect(button.toolTip?.contains(failure.message) == false)
		#expect(button.accessibilityLabel()?.contains(failure.message) == false)
	}

	private func change(_ diff: String) -> FileChange
	{
		FileChange(json: ["path": "same.swift", "kind": "update", "diff": diff])!
	}
}
