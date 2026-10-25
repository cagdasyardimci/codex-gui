import AppKit
import Testing

@testable import CodexGUI

@Suite
struct WindowLayoutTests
{

	@MainActor
	private func findChangesTabs(in view: NSView) -> NSSegmentedControl?
	{
		if let tabs = view as? NSSegmentedControl, tabs.accessibilityLabel() == "Changes detail tab"
		{
			return tabs
		}
		return view.subviews.lazy.compactMap
		{
			findChangesTabs(in: $0)
		}.first
	}

	@MainActor
	private func findModelSelection(in view: NSView) -> ModelEffortSelectionButton?
	{
		if let button = view as? ModelEffortSelectionButton
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findModelSelection(in: $0)
		}.first
	}

	// Presenting this fixture changes application-wide key-window state.
	@Test(.testTiming)
	@MainActor
	func windowAndCollapsedReviewSurviveRecreation() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		// Framework admission happens before the permit, while both native windows and
		// their cleanup stay in the same protected interval.
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			timing.mark("native.begin")
			_ = NSApplication.shared
			let suite = "WindowLayoutTests.\(UUID())"
			let defaults = try #require(UserDefaults(suiteName: suite))
			defer
			{
				defaults.removePersistentDomain(forName: suite)
			}
			let store = WindowLayoutStore(defaults: defaults)
			let screen = try #require(NSScreen.main?.visibleFrame)
			let expectedFrame = CGRect(
				x: screen.minX,
				y: screen.minY,
				width: min(
					900,
					screen.width
				),
				height: min(
					560,
					screen.height
				)
			)
			try #require(expectedFrame.width >= 800 && expectedFrame.height >= 500)
			store.layout = WindowLayout(
				frame: expectedFrame,
				navigationWidth: 240,
				reviewWidth: 280,
				reviewCollapsed: true,
				navigationCollapsed: false,
				paneGeometryVersion: WindowPaneLayout.version,
				reviewVisibility: .collapsed
			)
			let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
			let first = MainWindowController(
				store: state.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				},
				layoutStore: store
			)
			let window = try #require(first.window)
			first.showWindow(nil)
			timing.mark("first.window.shown")
			defer
			{
				window.orderOut(nil)
			}
			let split = first.paneController.split
			split.view.layoutSubtreeIfNeeded()
			#expect(window.frame == expectedFrame)
			#expect(abs(split.splitViewItems[0].viewController.view.frame.width - 240) < 2)
			first.paneController.toggleReview()
			first.paneController.toggleReview()
			#expect(split.splitViewItems[2].isCollapsed)
			let changedFrame = CGRect(
				x: expectedFrame.minX,
				y: expectedFrame.minY,
				width: max(
					800,
					expectedFrame.width - 40
				),
				height: max(
					500,
					expectedFrame.height - 40
				)
			)
			window.setFrame(
				changedFrame,
				display: false
			)
			first.paneController.setSidebarCollapsed(true)
			window.layoutIfNeeded()
			#expect(split.splitViewItems[0].isCollapsed)
			first.saveLayout()
			let saved = try #require(store.layout)
			#expect(saved.frame == changedFrame)
			#expect(saved.navigationWidth == 240)
			#expect(saved.reviewWidth == 280)
			#expect(saved.reviewCollapsed)
			#expect(saved.navigationCollapsed == true)
			let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
			let reopenedStore = WindowLayoutStore(defaults: reopenedDefaults)
			#expect(reopenedStore.layout == saved)
			let second = MainWindowController(
				store: state.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				},
				layoutStore: reopenedStore
			)
			let restored = try #require(second.window)
			let restoredSplit = second.paneController.split
			second.showWindow(nil)
			timing.mark("second.window.shown")
			defer
			{
				restored.orderOut(nil)
			}
			restoredSplit.view.layoutSubtreeIfNeeded()
			#expect(restoredSplit.splitViewItems[2].isCollapsed)
			#expect(restoredSplit.splitViewItems[0].isCollapsed)
			second.paneController.setSidebarCollapsed(false)
			restored.layoutIfNeeded()
			restoredSplit.view.layoutSubtreeIfNeeded()
			#expect(
				abs(restoredSplit.splitViewItems[0].viewController.view.frame.width - 240)
					< 2
			)
			#expect(restored.frame == changedFrame)
		}

	}
}
