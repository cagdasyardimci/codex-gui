import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationStartupLayoutTests
{
	@Test func compactPaneKeepsComposerControlHeightsBeforeFirstSnapshot()
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let view = controller.view
		#expect(controller.requestDetailsScrollView.isHidden)
		#expect(controller.attachmentDetailsScrollView.isHidden)
		#expect(view.fittingSize.height <= 278)

		view.frame = NSRect(
			x: 0,
			y: 0,
			width: 360,
			height: 278
		)
		view.layoutSubtreeIfNeeded()
		#expect(controller.requestDetailsScrollView.isHidden)
		#expect(controller.conversationScrollView.frame.height >= 64)
		#expect(controller.composerScrollView.frame.height >= 46)
		#expect(controller.addContextButton.frame.height == 24)
		#expect(controller.approvalPolicyButton.frame.height == 24)
		#expect(controller.modelEffortButton.frame.height == 28)
		#expect(controller.sendButton.frame.height == 28)
	}
}
