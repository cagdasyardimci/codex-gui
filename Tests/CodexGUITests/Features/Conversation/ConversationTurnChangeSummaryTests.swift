import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnChangeSummaryTests
{
	@Test func aggregateTurnDiffTakesPrecedenceOverReportedItems() throws
	{
		let diff = "diff --git a/Sources/First.swift b/Sources/First.swift\n"
			+ "--- a/Sources/First.swift\n+++ b/Sources/First.swift\n"
			+ "@@ -1 +1 @@\n-old\n+new\n"
		let summary = try #require(ConversationTurnChangeSummary(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot(activeTurnDiff: diff)
		))
		#expect(summary.fileCount == 1)
		#expect(summary.additions == 1)
		#expect(summary.deletions == 1)
		#expect(ConversationTurnChangeSummary(ConversationTurnChangeSummaryTestFixture
				.makeSnapshot(activeTurnDiff: "")) == nil)
	}
}
