import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationReplyActionLifecycleTests
{

	private func assertFollowingBottom(_ controller: ConversationViewController) throws
	{
		let layout = try #require(controller.transcript.collectionView
			.collectionViewLayout as? ConversationFlowLayout)
		let last = try #require(controller.transcript.displayedRows.last)
		let lastFrame = try frame(
			for: last.id,
			in: controller
		)
		let clip = controller.transcript.conversationScrollView.contentView
		let contentHeight = layout.collectionViewContentSize.height
		try #require(contentHeight > clip.bounds.height)
		#expect(controller.transcript.collectionView.isFlipped)
		#expect(abs(contentHeight - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(abs(clip.bounds.maxY - contentHeight) < 0.5)
		#expect(abs(clip.bounds.maxY - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(controller.transcript.isNearBottom)
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
		window.prepareForTesting()
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
		#expect(controller.transcript.replyActionEntryID == "first:reply")
		let firstHeight = try frame(
			for: "first:reply",
			in: controller
		).height
		let firstBookmark = try #require(button(
			"Bookmark turn",
			in: controller.transcript.collectionView
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
		#expect(controller.transcript.replyActionEntryID == nil)
		let bodyHeight = try frame(
			for: "first:reply",
			in: controller
		).height
		#expect(abs(firstHeight - bodyHeight - 34.5) < 0.5)
		#expect(button(
			"Copy response",
			in: controller.transcript.collectionView
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
		#expect(controller.transcript.replyActionEntryID == "second:reply")
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == bodyHeight)
		let previousConversationButton = try #require(button(
			"Bookmark turn",
			in: controller.transcript.collectionView
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
			in: controller.transcript.collectionView
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
		controller.transcript.collectionView.layoutSubtreeIfNeeded()
	}

	private func frame(
		for id: String,
		in controller: ConversationViewController
	) throws -> NSRect
	{
		let index = try #require(controller.transcript.displayedRows.firstIndex
		{
			$0.id == id
		})
		return try #require(controller.transcript.collectionView
			.layoutAttributesForItem(at: IndexPath(
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
