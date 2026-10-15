import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationReplyActionLifecycleTests
{
	@Test func followingOutputIncludesTrailingSpaceAfterReplyAndResize() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		let entries = (0 ..< 40).map
		{
			entry(
				"turn-\($0):reply",
				kind: .agent
			)
		}
		var snapshot = snapshot(entries: entries)
		snapshot.turnTimings = [ConversationTurnTiming(
			turnID: "turn-39",
			status: "completed"
		)]
		await render(
			snapshot,
			in: controller
		)
		controller.restoreReadingPosition(
			followOutput: true,
			anchor: nil
		)
		try assertFollowingBottom(controller)

		// The explicit latest action uses the same extent after the reader scrolls away.
		let clip = controller.conversationScrollView.contentView
		clip.scroll(to: .zero)
		controller.readingPositionChanged()
		#expect(!controller.latestButton.isHidden)
		controller.showLatestMessage()
		try assertFollowingBottom(controller)
		#expect(controller.latestButton.isHidden)

		// A new terminal reply changes both the row height and action ownership.
		snapshot = self.snapshot(entries: entries + [entry(
			"turn-40:reply",
			kind: .agent
		)])
		snapshot.turnTimings = [ConversationTurnTiming(
			turnID: "turn-40",
			status: "completed"
		)]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.replyActionEntryID == "turn-40:reply")
		try assertFollowingBottom(controller)

		controller.beginTranscriptResize(reason: .window)
		window.setContentSize(NSSize(
			width: 720,
			height: 760
		))
		controller.view.layoutSubtreeIfNeeded()
		controller.collectionView.layoutSubtreeIfNeeded()
		controller.endTranscriptResize(reason: .window)
		try assertFollowingBottom(controller)
	}

	private func assertFollowingBottom(_ controller: ConversationViewController) throws
	{
		let layout = try #require(controller.collectionView
			.collectionViewLayout as? ConversationFlowLayout)
		let last = try #require(controller.displayedRows.last)
		let lastFrame = try frame(
			for: last.id,
			in: controller
		)
		let clip = controller.conversationScrollView.contentView
		let contentHeight = layout.collectionViewContentSize.height
		try #require(contentHeight > clip.bounds.height)
		#expect(controller.collectionView.isFlipped)
		#expect(abs(contentHeight - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(abs(clip.bounds.maxY - contentHeight) < 0.5)
		#expect(abs(clip.bounds.maxY - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(controller.isNearBottom)
	}

	@Test func replyActionsFollowTerminalTurnsAndRejectPreviousConversationCallbacks() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		var toggled: [ConversationBookmark] = []
		controller.onToggleBookmark =
		{
			toggled.append($0)
		}
		let first = [
			entry(
				"first:request",
				kind: .user
			),
			entry(
				"first:reply",
				kind: .agent
			),
		]
		var snapshot = snapshot(entries: first)
		let firstTiming = ConversationTurnTiming(
			turnID: "first",
			status: "completed"
		)
		snapshot.turnTimings = [firstTiming]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.replyActionEntryID == "first:reply")
		let firstHeight = try frame(
			for: "first:reply",
			in: controller
		).height
		let firstBookmark = try #require(button(
			"Bookmark turn",
			in: controller.collectionView
		))
		firstBookmark.performClick(nil)
		let bookmark = try #require(toggled.first)
		#expect(bookmark.threadID == "chat" && bookmark.turnID == "first")
		#expect(bookmark.itemID == "reply" && bookmark.kind == .answer)

		// A bookmark publication changes only navigation, leaving the same transcript item alive.
		snapshot.projectContext.bookmarks = [bookmark]
		await render(
			snapshot,
			in: controller
		)
		#expect(firstBookmark.accessibilityLabel() == "Remove turn bookmark")
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == firstHeight)

		snapshot = self.snapshot(entries: first + [entry(
			"second:request",
			kind: .user
		)])
		snapshot.turnTimings = [firstTiming]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.replyActionEntryID == nil)
		let bodyHeight = try frame(
			for: "first:reply",
			in: controller
		).height
		#expect(abs(firstHeight - bodyHeight - 34.5) < 0.5)
		#expect(button(
			"Copy response",
			in: controller.collectionView
		) == nil)

		let secondEntries = snapshot.entries + [entry(
			"second:reply",
			kind: .agent
		)]
		snapshot = self.snapshot(entries: secondEntries)
		let secondTiming = ConversationTurnTiming(
			turnID: "second",
			status: "completed"
		)
		snapshot.turnTimings = [firstTiming, secondTiming]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.replyActionEntryID == "second:reply")
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == bodyHeight)
		let previousConversationButton = try #require(button(
			"Bookmark turn",
			in: controller.collectionView
		))

		snapshot = self.snapshot(
			entries: secondEntries,
			threadID: "another-chat"
		)
		snapshot.turnTimings = [firstTiming, secondTiming]
		await render(
			snapshot,
			in: controller
		)
		previousConversationButton.performClick(nil)
		#expect(toggled.count == 1)
		let currentBookmark = try #require(button(
			"Bookmark turn",
			in: controller.collectionView
		))
		currentBookmark.performClick(nil)
		#expect(toggled.count == 2)
		#expect(toggled.last?.threadID == "another-chat" && toggled.last?.turnID == "second")
	}

	private func render(
		_ snapshot: ConversationSnapshot,
		in controller: ConversationViewController
	) async
	{
		controller.render(snapshot)
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		controller.collectionView.layoutSubtreeIfNeeded()
	}

	private func frame(
		for id: String,
		in controller: ConversationViewController
	) throws -> NSRect
	{
		let index = try #require(controller.displayedRows.firstIndex
		{
			$0.id == id
		})
		return try #require(controller.collectionView.layoutAttributesForItem(at: IndexPath(
			item: index,
			section: 0
		))).frame
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label,
			!button.isHiddenOrHasHiddenAncestor
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func entry(
		_ id: String,
		kind: ConversationEntryKind
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: kind == .user ? "You" : "Codex",
			body: "First paragraph.\n\nSecond paragraph keeps the response height measurable."
		)
	}

	private func snapshot(
		entries: [ConversationEntry],
		threadID: String = "chat"
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/reply-actions",
			threads: [],
			selectedThreadID: threadID,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Synthetic",
			backendDescription: "Synthetic",
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
