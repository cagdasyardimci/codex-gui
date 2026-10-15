import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsToolbarIsolationTests
{
	@Test func retainedWindowsKeepIndependentToolbarCompositions() async throws
	{
		_ = NSApplication.shared
		let firstDefaults = try IsolatedUserDefaultsFixture(prefix: "FirstToolbarWindow")
		let secondDefaults = try IsolatedUserDefaultsFixture(prefix: "SecondToolbarWindow")
		defer
		{
			firstDefaults.cleanup()
			secondDefaults.cleanup()
		}
		let firstState =
			WorkspaceTestFixture(storage: LocalStorage(defaults: firstDefaults.defaults))
		let secondState =
			WorkspaceTestFixture(storage: LocalStorage(defaults: secondDefaults.defaults))
		defer
		{
			firstState.shutdown()
			secondState.shutdown()
		}
		let first = MainWindowController(
			store: firstState.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			},
			layoutStore: WindowLayoutStore(defaults: firstDefaults.defaults)
		)
		let firstWindow = try #require(first.window)
		defer
		{
			firstWindow.close()
		}
		let firstToolbar = try #require(firstWindow.toolbar)
		firstWindow.setContentSize(NSSize(
			width: 1512,
			height: 876
		))
		first.paneController.didPresentWindow()
		let firstClosedItems = firstToolbar.items.map(\.itemIdentifier)
		first.inspector.showToolsPane()
		first.paneController.setReviewCollapsed(false)
		first.updateToolsToolbarControls()
		firstWindow.layoutIfNeeded()
		let firstOpenItems = firstToolbar.items.map(\.itemIdentifier)
		try #require(firstOpenItems.contains(MainWindowController.ToolbarItem.toolsTabBar))

		let second = MainWindowController(
			store: secondState.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			},
			layoutStore: WindowLayoutStore(defaults: secondDefaults.defaults)
		)
		let secondWindow = try #require(second.window)
		defer
		{
			secondWindow.close()
		}
		let secondToolbar = try #require(secondWindow.toolbar)
		secondWindow.setContentSize(NSSize(
			width: 1512,
			height: 876
		))
		second.paneController.didPresentWindow()
		let secondClosedItems = secondToolbar.items.map(\.itemIdentifier)
		#expect(!secondClosedItems.contains(MainWindowController.ToolbarItem.toolsTabBar))
		#expect(firstToolbar.items.map(\.itemIdentifier) == firstOpenItems)

		for _ in 0 ..< 3
		{
			first.paneController.toggleToolsExpanded()
			try await waitForExpansion(first)
			first.updateToolsToolbarControls()
			#expect(first.paneController.isToolsExpanded)
			let firstExpandedItems = firstToolbar.items.map(\.itemIdentifier)
			#expect(firstExpandedItems != firstOpenItems)
			#expect(secondToolbar.items.map(\.itemIdentifier) == secondClosedItems)

			second.inspector.showToolsPane()
			second.paneController.setReviewCollapsed(false)
			second.updateToolsToolbarControls()
			secondWindow.layoutIfNeeded()
			#expect(secondToolbar.items.map(\.itemIdentifier).contains(
				MainWindowController.ToolbarItem.toolsTabBar
			))
			#expect(firstToolbar.items.map(\.itemIdentifier) == firstExpandedItems)

			second.inspector.closeToolsPane()
			second.paneController.setReviewCollapsed(true)
			second.updateToolsToolbarControls()
			secondWindow.layoutIfNeeded()
			#expect(secondToolbar.items.map(\.itemIdentifier) == secondClosedItems)
			#expect(firstToolbar.items.map(\.itemIdentifier) == firstExpandedItems)

			first.paneController.toggleToolsExpanded()
			try await waitForExpansion(first)
			first.updateToolsToolbarControls()
			#expect(!first.paneController.isToolsExpanded)
			#expect(firstToolbar.items.map(\.itemIdentifier) == firstOpenItems)

			first.inspector.closeToolsPane()
			first.paneController.setReviewCollapsed(true)
			first.updateToolsToolbarControls()
			firstWindow.layoutIfNeeded()
			#expect(firstToolbar.items.map(\.itemIdentifier) == firstClosedItems)
			#expect(secondToolbar.items.map(\.itemIdentifier) == secondClosedItems)

			first.inspector.showToolsPane()
			first.paneController.setReviewCollapsed(false)
			first.updateToolsToolbarControls()
			firstWindow.layoutIfNeeded()
			#expect(firstToolbar.items.map(\.itemIdentifier) == firstOpenItems)
			#expect(secondToolbar.items.map(\.itemIdentifier) == secondClosedItems)
		}
		first.inspector.closeToolsPane()
		first.paneController.setReviewCollapsed(true)
		first.updateToolsToolbarControls()
		#expect(firstToolbar.items.map(\.itemIdentifier) == firstClosedItems)
		#expect(secondToolbar.items.map(\.itemIdentifier) == secondClosedItems)
	}

	private func waitForExpansion(_ controller: MainWindowController) async throws
	{
		// Observe the actual transition completion even when other fixtures occupy MainActor.
		await controller.paneController.waitForToolsTransition()
		try #require(!controller.paneController.isAnimatingToolsExpansion)
		controller.window?.layoutIfNeeded()
	}
}
