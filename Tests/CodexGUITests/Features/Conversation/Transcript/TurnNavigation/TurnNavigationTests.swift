import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationTests
{
	// Native event polling and transient panels share the application event/window state.
	@Test(
		.testTiming
	)
	func railJumpsBookmarksAndClearsOnChatSwitch() async throws
	{
		let body = TestTiming.begin("test.body")
		defer
		{
			body.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			let nativeFixture = TestTiming.begin("fixture.window.construct")
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 800,
					height: 700
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			// Release the preview and window even when a required assertion throws.
			defer
			{
				let cleanup = TestTiming.begin("native.window.cleanup")
				controller.transcript.turnNavigationRail.dismissPreview()
				controller.transcript.collectionView.dataSource = nil
				controller.transcript.collectionView.delegate = nil
				window.contentViewController = nil
				window.close()
				cleanup.end()
			}
			window.contentViewController = controller
			// Attaching the controller can resize the window;
			// establish its viewport before rendering.
			window.setContentSize(NSSize(
				width: 800,
				height: 700
			))
			controller.view.layoutSubtreeIfNeeded()
			nativeFixture.end()
			let initialRender = TestTiming.begin("render.request.initial")
			controller.render(snapshot([
				entry(
					"first:request",
					.user,
					"First request"
				),
				entry(
					"first:reply",
					.agent,
					String(
						repeating: "Response\n",
						count: 40
					)
				),
				entry(
					"second:request",
					.user,
					"Second request"
				),
				entry(
					"second:reply",
					.agent,
					"Second reply"
				),
			]))
			initialRender.end()
			let initialRendering = TestTiming.begin("render.await.initial")
			await controller.waitForRendering()
			initialRendering.end()
			controller.view.layoutSubtreeIfNeeded()
			let rail = controller.transcript.turnNavigationRail
			#expect(rail.summaries.count == 2)
			#expect(!rail.isHidden)
			#expect(rail.activeTurnID == "second")
			let summary = try #require(rail.summaries.first)
			let railScroll = try #require(rail.subviews.first as? NSScrollView)
			let mark = try #require(railScroll.documentView?.subviews.first as? NSButton)
			let hover = try #require(NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			))
			let showPanel = TestTiming.begin("native.preview.show")
			mark.mouseEntered(with: hover)
			showPanel.end()
			let panel = try #require(rail.previewPanel)
			#expect(panel.parent === window)
			#expect(panel.styleMask.contains(.nonactivatingPanel))
			#expect(panel.contentView is TurnSummaryPreview)
			#expect(panel.frame.width == TurnSummaryPreview.cardWidth)
			try #require(mark.isEnabled)
			// Test the mark's configured jump action without performClick's native event polling,
			// whose HIToolbox wakeup can terminate SwiftPM's async-main loop before the next test.
			try #require(mark.sendAction(
				try #require(mark.action),
				to: mark.target
			))
			#expect(rail.previewPanel == nil)
			#expect(controller.transcript.collectionView.selectionIndexPaths == [IndexPath(
				item: 0,
				section: 0
			)])
			#expect(rail.activeTurnID == "first")
			let firstRow = try #require(controller.transcript.collectionView
				.layoutAttributesForItem(
					at: IndexPath(
						item: 0,
						section: 0
					)
				))
			let readingColumn = controller.view.convert(
				firstRow.frame,
				from: controller.transcript.collectionView
			)
			#expect(rail.frame.maxX <= readingColumn.minX)
			var toggled: ConversationBookmark?
			controller.onToggleBookmark =
			{
				toggled = $0
			}
			rail.onBookmark?(summary)
			let bookmark = try #require(toggled)
			#expect(bookmark.threadID == "thread")
			#expect(bookmark.turnID == "first")
			#expect(bookmark.itemID == "request")
			controller.transcript.bookmarks = [bookmark]
			#expect(rail.isBookmarked?(summary) == true)
			var other = snapshot([])
			other = ConversationSnapshot(
				projectPath: other.projectPath,
				threads: [],
				selectedThreadID: "other",
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
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
			let switchedRender = TestTiming.begin("render.request.switch")
			controller.render(other)
			switchedRender.end()
			#expect(rail.summaries.isEmpty)
			#expect(rail.isHidden)
			toggled = nil
			rail.onBookmark?(summary)
			#expect(toggled == nil)
			let switchedRendering = TestTiming.begin("render.await.switch")
			await controller.waitForRendering()
			switchedRendering.end()
		}
	}

	@Test(arguments: [12, 96])
	func scrollingTranscriptChangesActiveTurnWithoutMovingRail(turnCount: Int) async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 800,
				height: 700
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.isReleasedWhenClosed = false
		window.setContentSize(NSSize(
			width: 800,
			height: 700
		))
		defer
		{
			controller.transcript.turnNavigationRail.dismissPreview()
			controller.transcript.collectionView.dataSource = nil
			controller.transcript.collectionView.delegate = nil
			window.contentViewController = nil
			window.close()
		}
		let entries = (0 ..< turnCount).flatMap
		{
			index in
			[
				entry(
					"turn-\(index):request",
					.user,
					"Request \(index)"
				),
				entry(
					"turn-\(index):reply",
					.agent,
					String(
						repeating: "Response text. ",
						count: 100
					)
				),
			]
		}
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		await settleTranscriptLayout(controller)
		let rail = controller.transcript.turnNavigationRail
		let latestTurnID = "turn-\(turnCount - 1)"
		#expect(rail.activeTurnID == latestTurnID)
		let railFrame = rail.frame
		let railScroll = try #require(rail.subviews.first as? NSScrollView)
		let railOrigin = railScroll.contentView.bounds.origin
		let transcript = controller.transcript.conversationScrollView
		#expect(controller.transcript.collectionView.bounds.height > transcript.contentView.bounds
			.height)
		transcript.contentView.scroll(to: .zero)
		transcript.reflectScrolledClipView(transcript.contentView)
		controller.transcript.readingPositionChanged()
		await settleTranscriptLayout(controller)
		#expect(rail.activeTurnID == "turn-0")
		#expect(!controller.transcript.latestButton.isHidden)
		#expect(rail.frame == railFrame)
		let firstMark = try #require(railScroll.documentView?.subviews.first)
		#expect(railScroll.contentView.bounds.contains(firstMark.frame))
		controller.transcript.showLatestMessage()
		await settleTranscriptLayout(controller)
		#expect(rail.activeTurnID == latestTurnID)
		#expect(controller.transcript.latestButton.isHidden)
		#expect(rail.frame == railFrame)
		#expect(railScroll.contentView.bounds.origin == railOrigin)
		for _ in 0 ..< 4
		{
			controller.transcript.readingPositionChanged()
		}
		await settleTranscriptLayout(controller)
		#expect(rail.activeTurnID == latestTurnID)
		#expect(rail.frame == railFrame)
		#expect(railScroll.contentView.bounds.origin == railOrigin)
	}

	private func settleTranscriptLayout(_ controller: ConversationViewController) async
	{
		for _ in 0 ..< 4
		{
			controller.view.layoutSubtreeIfNeeded()
			controller.transcript.collectionView.layoutSubtreeIfNeeded()
			// Width-change restoration is owned by this controller, not a fixed delay.
			await controller.transcript.widthChangeRestoreTask?.value
		}
	}

	private func entry(
		_ id: String,
		_ kind: ConversationEntryKind,
		_ body: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "",
			body: body
		)
	}

	private func snapshot(_ entries: [ConversationEntry]) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/turn-navigation",
			threads: [],
			selectedThreadID: "thread",
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
