import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct VisibleGitReviewTurnTests
{
	@Test func runningTurnReviewDoesNotUsePreviousTurnsReportedChanges() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		snapshot.lastGitTurnID = "previous"
		snapshot.reportedGitTurnID = "previous"
		snapshot.reportedGitChanges = [FileChange(json: [
			"path": "Old.swift",
			"kind": "update",
		])!]
		#expect(snapshot.visibleGitReviewTurn.id == "turn")
		#expect(snapshot.visibleGitReviewTurn.changes == nil)
	}
}
