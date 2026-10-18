import AppKit
import Testing

@testable import CodexGUI

@Suite
struct WindowLayoutTests
{
	@Test func toolsPaneReservesA320PointConversationViewport()
	{
		let layout = WindowPaneLayoutPolicy.reviewLayout(
			width: 1512,
			navigationCollapsed: false,
			navigationWidth: 326,
			dividerThickness: 2.25,
			isToolsExpanded: false,
			usesToolsSizing: true,
			workspaceFilesExpanded: false,
			expandedToolsWidth: 1200,
			workspaceFilesWidth: 760,
			expandedReviewWidth: 326,
			reviewVisibility: .expanded
		)
		#expect(!layout.collapsed)
		#expect(layout.width == 861.5)
	}

	@Test(.testTiming)
	@MainActor
	func fullMinimumWindowFrameFitsConversationAndChanges() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			timing.mark("native.begin")
			// Reserve native fixture construction and presentation after case admission.
			// This empty-transcript fixture checks synchronous pane and composer geometry;
			// text preparation and scroll-anchor tasks do not contribute to these assertions.
			_ = NSApplication.shared
			let suite = "WindowLayoutMinimumTests.\(UUID())"
			let defaults = try #require(UserDefaults(suiteName: suite))
			defer
			{
				defaults.removePersistentDomain(forName: suite)
			}
			let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
			defer
			{
				state.shutdown()
			}
			let controller = MainWindowController(
				store: state.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				}
			)
			let window = try #require(controller.window)
			defer
			{
				window.close()
				timing.mark("window.dismissed")
			}
			timing.mark("fixture.ready")
			let split = controller.paneController.split
			#expect(split.splitViewItems[1].maximumThickness == NSSplitViewItem
				.unspecifiedDimension)
			let navigation = try #require(
				split.splitViewItems[0].viewController as? NavigationViewController
			)
			let inspector = try #require(split.splitViewItems[2]
				.viewController.children.first as? InspectorViewController)
			let model = try #require(
				ModelOption(json: [
					"model": "gpt-6-astra",
					"displayName": "GPT6-ASTRA",
					"isDefault": true,
					"supportedReasoningEfforts": [["reasoningEffort": "high"]],
				])
			)
			var snapshot = ConversationSnapshot(
				projectPath: nil,
				threads: [],
				selectedThreadID: nil,
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Mock",
				backendDescription: "Mock",
				executionState: .ready,
				statusMessage: nil,
				models: [model],
				selectedModelID: model.id,
				selectedEffort: "high",
				pendingInteractions: [],
				recentProjects: []
			)
			snapshot.activeThreadID = "stopped-task"
			snapshot.activeExecutionState = .stopped
			let hunk = ReviewHunk(
				id: "hunk",
				header: "@@ -1 +1 @@",
				text: "@@ -1 +1 @@\n-old\n+new",
				fingerprint: "hunk"
			)
			let file = ReviewFile(
				path: "Sources/A-long-renamed-file.swift",
				previousPath: "Sources/Original.swift",
				reportedMovePath: nil,
				kind: .renamed,
				hunks: [hunk],
				diff: hunk.text,
				fingerprint: "file",
				explanation: nil
			)
			let command = ReviewValidation(
				threadID: "thread-with-a-long-identity",
				turnID: "earlier-turn",
				itemID: "test",
				command: "swift test --filter EarlierCompatibilityTests",
				cwd: "/tmp/project",
				output: "1 test passed",
				exitCode: 0,
				outcome: .succeeded,
				currency: .outdated,
				codeStateID: "before-edit",
				hasUnknownEarlierHistory: true
			)
			let review = ReviewTurn(
				threadID: command.threadID,
				turnID: command.turnID,
				files: [file],
				validations: [command],
				codeStateID: "after-edit",
				hasUnknownEarlierHistory: true
			)
			snapshot.reviewTurns = [review]
			snapshot.selectedReviewTurnID = review.turnID
			snapshot.selectedReview = review
			navigation.render(snapshot)
			inspector.changes.render(snapshot)
			let conversation = try #require(
				split.splitViewItems[1].viewController.children.first as? ConversationViewController
			)
			conversation.render(snapshot)
			timing.mark("snapshot.rendered")
			controller.showWindow(nil)
			timing.mark("window.shown")
			window.layoutIfNeeded()
			window.update()
			#expect(window.minSize == NSSize(
				width: 800,
				height: 500
			))
			for showReview in [false, true]
			{
				timing.mark(showReview ? "review.resize.begin" : "navigation.resize.begin")
				window.setFrame(
					NSRect(
						x: 100,
						y: 100,
						width: 800,
						height: 500
					),
					display: false
				)
				if showReview
				{
					// At the compact width, hide the sidebar before opening the review pane.
					// Review geometry is independent of toolbar chrome.
					controller.paneController.toggleSidebar()
					controller.paneController.toggleReview()
				}
				window.layoutIfNeeded()
				split.view.layoutSubtreeIfNeeded()
				#expect(split.splitViewItems[2].isCollapsed == !showReview)
				#expect(split.splitViewItems[0].isCollapsed == showReview)
				#expect(conversation.view.frame.width >= 360)
				let visiblePane = showReview ? inspector.view : navigation.view
				#expect(!visiblePane.isHiddenOrHasHiddenAncestor)
				#expect(visiblePane.frame.width >= (showReview ? 220 : 200))
				#expect(split.view.bounds.contains(visiblePane.convert(
					visiblePane.bounds,
					to: split.view
				)))
				#expect(window.frame.size == NSSize(
					width: 800,
					height: 500
				))
				SplitPaneLayoutChecks.verifyVisiblePanesFit(split)
				let selection = try #require(findModelSelection(in: conversation.view))
				#expect(selection.frame.width > 0)
				#expect(
					conversation.view.bounds.contains(
						selection.convert(
							selection.bounds,
							to: conversation.view
						)
					)
				)
				#expect(selection.title == "GPT6-ASTRA High")
				#expect(selection.toolTip == "GPT6-ASTRA High")
				timing.mark(showReview ? "review.verified" : "navigation.verified")
			}
			#expect(findChangesTabs(in: inspector.changes.view) == nil)
			let inspectorScroll = try #require(inspector.changes.view as? NSScrollView)
			#expect(
				try #require(inspectorScroll.documentView).frame.height
					>= inspectorScroll.contentSize.height
			)
		}
	}

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

	@Test func removedDisplayFrameReturnsToVisibleScreen()
	{
		let saved = WindowLayout(
			frame: CGRect(
				x: 2200,
				y: 100,
				width: 1400,
				height: 900
			),
			navigationWidth: 240,
			reviewWidth: 280,
			reviewCollapsed: true
		)
		let screen = CGRect(
			x: 0,
			y: 40,
			width: 1280,
			height: 760
		)
		let restored = saved.visibleFrame(
			on: [screen],
			minimumSize: CGSize(
				width: 800,
				height: 500
			)
		)
		#expect(screen.contains(restored))
		#expect(restored.size == screen.size)
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
			defer
			{
				state.shutdown()
			}
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
				window.close()
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
				restored.close()
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
