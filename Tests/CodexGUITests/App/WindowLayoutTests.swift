import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct WindowLayoutTests
{
	@Test func fullMinimumWindowFrameFitsConversationAndChanges() async throws
	{
		_ = NSApplication.shared
		let suite = "WindowLayoutMinimumTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
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
		let split = try #require(window.contentViewController as? NSSplitViewController)
		let navigation = try #require(
			split.splitViewItems[0].viewController as? NavigationViewController
		)
		let inspector = try #require(split.splitViewItems[2]
			.viewController as? InspectorViewController)
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
			split.splitViewItems[1].viewController as? ConversationViewController
		)
		conversation.render(snapshot)
		controller.showWindow(nil)
		defer
		{
			window.orderOut(nil)
		}
		try await Task.sleep(for: .milliseconds(30))
		window.layoutIfNeeded()
		window.update()
		#expect(window.minSize == NSSize(
			width: 800,
			height: 500
		))
		for showReview in [false, true]
		{
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
				// Both panes remain accessible through their toolbar controls.
				try activateToolbarItem(
					"sidebar",
					in: window
				)
				try activateToolbarItem(
					"review",
					in: window
				)
			}
			try await Task.sleep(for: .milliseconds(30))
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
			#expect(split.view.fittingSize.width <= split.view.bounds.width + 1)
			#expect(split.view.fittingSize.height <= split.view.bounds.height + 1)
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
		}
		let tabs = try #require(findChangesTabs(in: inspector.changes.view))
		for tab in [1, 0, 1]
		{
			tabs.selectedSegment = tab
			_ = tabs.target?.perform(
				tabs.action,
				with: tabs
			)
			window.update()
			split.view.layoutSubtreeIfNeeded()
			#expect(window.minSize == NSSize(
				width: 800,
				height: 500
			))
			#expect(window.frame.size == NSSize(
				width: 800,
				height: 500
			))
			let inspectorScroll = try #require(inspector.changes.view as? NSScrollView)
			#expect(
				try #require(inspectorScroll.documentView).frame.height
					>= inspectorScroll.contentSize.height
			)
		}
	}

	private func activateToolbarItem(
		_ identifier: String,
		in window: NSWindow
	) throws
	{
		let item = try #require(
			window.toolbar?.items.first
			{
				$0.itemIdentifier.rawValue == identifier
			}
		)
		let action = try #require(item.action)
		#expect(NSApp.sendAction(
			action,
			to: item.target,
			from: item
		))
	}

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

	@Test func windowAndCollapsedReviewSurviveRecreation() throws
	{
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
		defer
		{
			window.orderOut(nil)
		}
		let split = try #require(window.contentViewController as? NSSplitViewController)
		split.view.layoutSubtreeIfNeeded()
		#expect(window.frame == expectedFrame)
		#expect(abs(split.splitViewItems[0].viewController.view.frame.width - 240) < 2)
		let reviewToggle = try #require(
			window.toolbar?.items.first
			{
				$0.itemIdentifier.rawValue == "review"
			}
		)
		let action = try #require(reviewToggle.action)
		_ = NSApp.sendAction(
			action,
			to: reviewToggle.target,
			from: reviewToggle
		)
		_ = NSApp.sendAction(
			action,
			to: reviewToggle.target,
			from: reviewToggle
		)
		#expect(split.splitViewItems[2].isCollapsed)
		first.saveLayout()
		let saved = try #require(store.layout)
		#expect(saved.frame == expectedFrame)
		#expect(saved.navigationWidth == 240)
		#expect(saved.reviewWidth == 280)
		#expect(saved.reviewCollapsed)
		let second = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			},
			layoutStore: store
		)
		let restored = try #require(second.window)
		let restoredSplit = try #require(restored.contentViewController as? NSSplitViewController)
		second.showWindow(nil)
		defer
		{
			restored.orderOut(nil)
		}
		restoredSplit.view.layoutSubtreeIfNeeded()
		#expect(restoredSplit.splitViewItems[2].isCollapsed)
		#expect(
			abs(restoredSplit.splitViewItems[0].viewController.view.frame.width - 240)
				< 2
		)
		#expect(restored.frame == expectedFrame)
	}
}
