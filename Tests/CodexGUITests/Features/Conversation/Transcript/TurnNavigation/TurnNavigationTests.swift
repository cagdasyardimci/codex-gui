import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationTests
{
	@Test func railJumpsBookmarksAndClearsOnChatSwitch() async throws
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
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		let rail = controller.turnNavigationRail
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
		mark.mouseEntered(with: hover)
		let panel = try #require(rail.previewPanel)
		#expect(panel.parent === window)
		#expect(panel.styleMask.contains(.nonactivatingPanel))
		#expect(panel.contentView is TurnSummaryPreview)
		#expect(panel.frame.width == TurnSummaryPreview.cardWidth)
		mark.performClick(nil)
		#expect(rail.previewPanel == nil)
		#expect(controller.collectionView.selectionIndexPaths == [IndexPath(
			item: 0,
			section: 0
		)])
		#expect(rail.activeTurnID == "first")
		let firstRow = try #require(controller.collectionView.layoutAttributesForItem(
			at: IndexPath(
				item: 0,
				section: 0
			)
		))
		let readingColumn = controller.view.convert(
			firstRow.frame,
			from: controller.collectionView
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
		controller.bookmarks = [bookmark]
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
		controller.render(other)
		#expect(rail.summaries.isEmpty)
		#expect(rail.isHidden)
		toggled = nil
		rail.onBookmark?(summary)
		#expect(toggled == nil)
		await controller.waitForRendering()
		window.contentViewController = nil
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
		window.setContentSize(NSSize(
			width: 800,
			height: 700
		))
		defer
		{
			controller.collectionView.dataSource = nil
			controller.collectionView.delegate = nil
			window.contentViewController = nil
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
		let rail = controller.turnNavigationRail
		let latestTurnID = "turn-\(turnCount - 1)"
		#expect(rail.activeTurnID == latestTurnID)
		let railFrame = rail.frame
		let railScroll = try #require(rail.subviews.first as? NSScrollView)
		let railOrigin = railScroll.contentView.bounds.origin
		let transcript = controller.conversationScrollView
		#expect(controller.collectionView.bounds.height > transcript.contentView.bounds.height)
		transcript.contentView.scroll(to: .zero)
		transcript.reflectScrolledClipView(transcript.contentView)
		controller.readingPositionChanged()
		await settleTranscriptLayout(controller)
		#expect(rail.activeTurnID == "turn-0")
		#expect(!controller.latestButton.isHidden)
		#expect(rail.frame == railFrame)
		let firstMark = try #require(railScroll.documentView?.subviews.first)
		#expect(railScroll.contentView.bounds.contains(firstMark.frame))
		controller.showLatestMessage()
		await settleTranscriptLayout(controller)
		#expect(rail.activeTurnID == latestTurnID)
		#expect(controller.latestButton.isHidden)
		#expect(rail.frame == railFrame)
		#expect(railScroll.contentView.bounds.origin == railOrigin)
		for _ in 0 ..< 4
		{
			controller.readingPositionChanged()
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
			controller.collectionView.layoutSubtreeIfNeeded()
			try? await Task.sleep(for: .milliseconds(10))
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
