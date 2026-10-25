import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct TurnChangeSummaryButtonTests
{
	@Test func previousTurnCountsExplainTheirSource() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		snapshot.reportedGitTurnID = "previous"
		let summary = try #require(ConversationTurnChangeSummary(snapshot))
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "2 files changed +3 -1")
		#expect(button.toolTip?.contains("Previous editing turn") == true)
		#expect(button.accessibilityLabel()?.contains("Previous editing turn") == true)
	}

	@Test(arguments: [GitComparisonFailure.lastTurnUnavailable,
						.oversized,
						.repositoryUnavailable,
						.cancelled,
						.failed("Preview failed")])
	func failuresKeepTheCountsWithoutDisplayingTheError(_ failure: GitComparisonFailure) throws
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
