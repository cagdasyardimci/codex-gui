import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationStartupLayoutTests
{
	@Test func transcriptAndComposerShareThePaneCenterAtBothWidths()
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let view = controller.view
		for width: CGFloat in [360, 1000]
		{
			view.frame = NSRect(
				x: 0,
				y: 0,
				width: width,
				height: 700
			)
			view.layoutSubtreeIfNeeded()
			let transcript = view.convert(
				controller.conversationScrollView.bounds,
				from: controller.conversationScrollView
			)
			let composer = view.convert(
				controller.composerScrollView.bounds,
				from: controller.composerScrollView
			)
			#expect(abs(transcript.midX - composer.midX) < 1)
			let rail = view.convert(
				controller.turnNavigationRail.bounds,
				from: controller.turnNavigationRail
			)
			#expect(transcript.minX + ConversationFlowLayout.minimumHorizontalInset >= rail.maxX)
		}
	}

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
		#expect(controller.composerScrollView.frame.height >= 44)
		#expect(controller.addContextButton.frame.height == 28)
		#expect(controller.approvalPolicyButton.frame.height == 28)
		#expect(controller.modelEffortButton.frame.height == 28)
		#expect(controller.sendButton.frame.height == 28)
	}
}
