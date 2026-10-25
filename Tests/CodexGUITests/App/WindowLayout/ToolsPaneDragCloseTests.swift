import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsPaneDragCloseTests
{
	@Test func reviewDividerFinishesClosingWithoutDiscardingToolsTabs() async throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: ConversationViewController(),
			inspector: inspector,
			layoutStore: nil
		)
		let chrome = WindowChromeViewController(
			split: panes.split,
			accountButton: NSButton()
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 760
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = chrome
		panes.restoreLayout(in: window)
		panes.didPresentWindow()
		defer
		{
			window.close()
		}
		#expect(panes.split.splitViewItems[1].minimumThickness == 360)
		panes.openToolsPane()
		if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			#expect(panes.isAnimatingToolsExpansion)
			#expect(panes.split.splitViewItems[1].minimumThickness == 0)
		}
		await panes.waitForToolsTransition()
		try #require(!panes.isAnimatingToolsExpansion && !panes.isReviewCollapsed)
		window.layoutIfNeeded()
		#expect(panes.split.splitViewItems[1].minimumThickness == 320)
		let tab = try #require(inspector.toolsTabs.selectedTabID)
		let count = inspector.toolsTabs.tabCount
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth)

		var finishedTransitions = 0
		var closingWidths: [CGFloat] = []
		panes.onToolsExpansionFinished =
		{
			finishedTransitions += 1
		}
		panes.onToolsExpansionLayoutChanged =
		{
			closingWidths.append(panes.reviewViewportWidth)
		}
		panes.beginDividerInteraction(at: 1)
		let split = panes.split.splitView
		split.setPosition(
			split.bounds.width - 300 - split.dividerThickness,
			ofDividerAt: 1
		)
		window.layoutIfNeeded()
		let releaseWidth = panes.reviewViewportWidth
		#expect(releaseWidth >= WindowPaneLayout.toolsMinimumWidth)
		panes.endDividerInteraction(
			at: 1,
			requestedWidth: 300
		)
		if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			#expect(panes.isAnimatingToolsExpansion)
		}
		await panes.waitForToolsTransition()
		try #require(!panes.isAnimatingToolsExpansion && panes.isReviewCollapsed)
		#expect(inspector.isShowingTools)
		#expect(inspector.toolsTabs.tabCount == count)
		#expect(inspector.toolsTabs.selectedTabID == tab)
		#expect(finishedTransitions == 1)
		#expect((closingWidths.max() ?? 0) <= releaseWidth + 2)

		panes.onToolsExpansionLayoutChanged = nil
		panes.openToolsPane()
		await panes.waitForToolsTransition()
		try #require(!panes.isAnimatingToolsExpansion && !panes.isReviewCollapsed)
		#expect(inspector.isShowingTools)
		#expect(inspector.toolsTabs.tabCount == count)
		#expect(inspector.toolsTabs.selectedTabID == tab)
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth)

		let transitionsBeforeWideDrag = finishedTransitions
		panes.beginDividerInteraction(at: 1)
		split.setPosition(
			split.bounds.width - 340 - split.dividerThickness,
			ofDividerAt: 1
		)
		window.layoutIfNeeded()
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth)
		panes.endDividerInteraction(
			at: 1,
			requestedWidth: 340
		)
		#expect(!panes.isReviewCollapsed)
		#expect(!panes.isAnimatingToolsExpansion)
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth)
		#expect(finishedTransitions == transitionsBeforeWideDrag)

		window.setContentSize(NSSize(
			width: 900,
			height: 760
		))
		window.layoutIfNeeded()
		#expect(panes.isReviewCollapsed)
		window.setContentSize(NSSize(
			width: 1200,
			height: 760
		))
		window.layoutIfNeeded()
		#expect(!panes.isReviewCollapsed)
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth)
		#expect(inspector.toolsTabs.selectedTabID == tab)

		inspector.showSummary()
		#expect(panes.split.splitViewItems[1].minimumThickness == 360)
		panes.openToolsPane()
		panes.beginDividerInteraction(at: 1)
		#expect(!panes.isAnimatingToolsExpansion)
		#expect(panes.split.splitViewItems[1].minimumThickness == 320)
		#expect(panes.split.splitViewItems[2].minimumThickness == 320)
		panes.endDividerInteraction(
			at: 1,
			requestedWidth: 340
		)

		inspector.showSummary()
		#expect(panes.split.splitViewItems[1].minimumThickness == 360)
		inspector.showToolsPane()
		panes.setReviewCollapsed(false)
		window.layoutIfNeeded()
		#expect(panes.split.splitViewItems[1].minimumThickness == 320)
		panes.toggleToolsExpanded()
		if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			#expect(panes.isAnimatingToolsExpansion)
			#expect(panes.split.splitViewItems[1].minimumThickness == 0)
		}
		// Retain the canceled operation so its unwind is verified without a delay.
		let canceledTransition = panes.toolsTransitionTask
		inspector.closeToolsPane()
		#expect(!inspector.isShowingTools)
		#expect(!panes.isToolsExpanded)
		#expect(!panes.isAnimatingToolsExpansion)
		#expect(panes.split.splitViewItems[1].minimumThickness == 360)
		#expect(panes.split.splitViewItems[2].minimumThickness == 220)
		await canceledTransition?.value
		#expect(!panes.isAnimatingToolsExpansion)
		#expect(panes.split.splitViewItems[1].minimumThickness == 360)
		#expect(panes.split.splitViewItems[2].minimumThickness == 220)
		#expect(inspector.toolsTabs.selectedTabID == tab)
	}

}
