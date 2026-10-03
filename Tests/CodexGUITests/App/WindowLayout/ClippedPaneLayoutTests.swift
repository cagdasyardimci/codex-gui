import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ClippedPaneLayoutTests
{
	@Test func contentHasSupportedGeometryBeforeFirstLayoutAndWhileCollapsed()
	{
		_ = NSApplication.shared
		let content = makeContent()
		let host = ClippedPaneViewController(
			content: content,
			minimumContentWidth: 180
		)
		_ = host.view
		#expect(content.view.frame.width >= 180)
		#expect(content.view.frame.height >= 144)
		host.view.setFrameSize(NSSize(
			width: 300,
			height: 400
		))
		host.view.layoutSubtreeIfNeeded()
		#expect(content.view.frame.size == NSSize(
			width: 300,
			height: 400
		))
		host.view.setFrameSize(.zero)
		host.view.layoutSubtreeIfNeeded()
		#expect(content.view.frame.width >= 180)
		#expect(content.view.frame.height >= 144)
		host.view.setFrameSize(NSSize(
			width: 260,
			height: 360
		))
		host.view.layoutSubtreeIfNeeded()
		#expect(content.view.frame.size == NSSize(
			width: 260,
			height: 360
		))
	}

	@Test func asideAndTransferredContentRetainSupportedGeometry()
	{
		_ = NSApplication.shared
		let content = makeContent()
		let aside = makeContent()
		let host = ClippedPaneViewController(
			content: content,
			minimumContentWidth: 180
		)
		host.setAside(
			aside,
			width: 200
		)
		#expect(aside.view.frame.width >= 200)
		#expect(aside.view.frame.height >= 144)
		host.view.setFrameSize(NSSize(
			width: 500,
			height: 400
		))
		host.view.layoutSubtreeIfNeeded()
		#expect(content.view.frame.width == 300)
		#expect(aside.view.frame == NSRect(
			x: 300,
			y: 0,
			width: 200,
			height: 400
		))
		host.detachContent()
		let destination = ClippedPaneViewController(
			content: content,
			minimumContentWidth: 180
		)
		_ = destination.view
		destination.view.layoutSubtreeIfNeeded()
		#expect(content.view.frame.width >= 180)
		#expect(content.view.frame.height >= 144)
	}

	@Test func conversationAndInspectorFitBeforeAttachmentAndAfterTransfer()
	{
		_ = NSApplication.shared
		let panes: [(NSViewController, CGFloat)] = [
			(ConversationViewController(), WindowPaneLayout.conversationMinimumWidth),
			(InspectorViewController(), WindowPaneLayout.reviewMinimumWidth),
		]
		for (content, width) in panes
		{
			let host = ClippedPaneViewController(
				content: content,
				minimumContentWidth: width
			)
			_ = host.view
			#expect(content.view.frame.width >= width)
			#expect(content.view.frame.height > 32)
			host.view.setFrameSize(NSSize(
				width: 900,
				height: 700
			))
			host.view.layoutSubtreeIfNeeded()
			host.detachContent()
			let destination = ClippedPaneViewController(
				content: content,
				minimumContentWidth: width
			)
			destination.view.setFrameSize(NSSize(
				width: width,
				height: 400
			))
			destination.view.layoutSubtreeIfNeeded()
			#expect(content.view.frame.size == NSSize(
				width: width,
				height: 400
			))
		}
	}

	private func makeContent() -> NSViewController
	{
		let controller = NSViewController()
		controller.view = NSView()
		let child = NSView()
		AppKitLayout.pin(
			child,
			to: controller.view,
			inset: 12
		)
		NSLayoutConstraint.activate([
			child.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
			child.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
		])
		return controller
	}
}
