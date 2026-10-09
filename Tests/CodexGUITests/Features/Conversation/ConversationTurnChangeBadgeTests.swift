import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnChangeBadgeTests
{
	@Test func badgeTracksOnlySelectedRunningTurnAndOpensChanges() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var opened = 0
		controller.onViewChanges =
		{
			opened += 1
		}
		let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		controller.render(snapshot)
		for _ in 0 ..< 100 where controller.turnChangeSummaryButton.attributedTitle.string
			!= "2 files changed +3 -1"
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(controller.turnChangeSummaryButton.isHidden == false)
		#expect(controller.turnChangeSummaryButton.attributedTitle.string
			== "2 files changed +3 -1")
		controller.turnChangeSummaryButton.performClick(nil)
		#expect(opened == 1)

		controller
			.render(ConversationTurnChangeSummaryTestFixture
				.makeSnapshot(selectedThreadID: "elsewhere"))
		#expect(controller.turnChangeSummaryButton.isHidden)

		controller
			.render(ConversationTurnChangeSummaryTestFixture
				.makeSnapshot(executionState: .completed))
		#expect(controller.turnChangeSummaryButton.isHidden)
	}
}
