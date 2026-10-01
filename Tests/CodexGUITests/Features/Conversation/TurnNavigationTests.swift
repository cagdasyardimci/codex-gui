import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationTests
{
	@Test func summariesGroupByTurnAndExcludeToolOutput()
	{
		let summaries = ConversationTurnSummary.make(from: [
			entry(
				"orphan:reply",
				.agent,
				"Older partial turn"
			),
			entry(
				"first:request",
				.user,
				"Fix\n the bug"
			),
			entry(
				"first:commentary",
				.agent,
				"Checking"
			),
			entry(
				"first:command",
				.command,
				"Sensitive tool output"
			),
			entry(
				"first:final",
				.agent,
				"Fixed the bug"
			),
			entry(
				"first:steer",
				.user,
				"Follow-up in the same turn"
			),
			entry(
				"second:request",
				.user,
				"Next request"
			),
		])
		#expect(summaries.map(\.turnID) == ["first", "second"])
		#expect(summaries[0].entryID == "first:request")
		#expect(summaries[0].title == "Fix the bug")
		#expect(summaries[0].reply == "Fixed the bug")
		#expect(summaries[1].reply.isEmpty)
	}

	@Test func previewsAreBoundedAndUpdateWhileStreaming()
	{
		let request = entry(
			"turn:request",
			.user,
			String(
				repeating: "x",
				count: 10000
			)
		)
		let pending = ConversationTurnSummary.make(from: [request])
		let complete = ConversationTurnSummary.make(from: [request,
															entry(
															"turn:reply",
															.agent,
															"Completed reply"
															)])
		#expect(pending[0].title.count == 400)
		#expect(complete[0].entryID == pending[0].entryID)
		#expect(complete[0].reply == "Completed reply")
	}

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
		#expect(rail.frame.maxX <= controller.conversationScrollView.frame.minX + 12)
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

	@Test func previewFitsAndBookmarkButtonDispatches() throws
	{
		_ = NSApplication.shared
		let summary = ConversationTurnSummary(
			turnID: "turn",
			entryID: "turn:request",
			title: String(
				repeating: "A long request ",
				count: 30
			),
			reply: String(
				repeating: "The reply contains details. ",
				count: 30
			)
		)
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: false
		)
		let window = NSWindow(
			contentRect: preview.bounds,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = preview
		window.displayIfNeeded()
		defer
		{
			window.contentView = nil
		}
		preview.layoutSubtreeIfNeeded()
		let stack = try #require(preview.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let button = try #require(header.arrangedSubviews.last as? NSButton)
		#expect(header.frame.width == preview.bounds.width - 20)
		#expect(header.frame.height >= 16)
		#expect(button.frame.width == 18)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		#expect(reply.frame.height > 40)
		#expect(reply.cell?.wraps == true)
		#expect(reply.stringValue.hasSuffix("…"))
		#expect(preview.cardHeight == preview.frame.height)
		let multilineHeight = preview.cardHeight
		preview.render(ConversationTurnSummary(
			turnID: "turn",
			entryID: "turn:request",
			title: "Short request",
			reply: "Short reply"
		))
		#expect(preview.cardHeight < multilineHeight)
		var clicked = false
		preview.onBookmark =
		{
			clicked = true
		}
		button.performClick(nil)
		#expect(clicked)
		preview.setBookmarked(true)
		#expect(button.accessibilityLabel() == "Remove turn bookmark")

	}

	@Test func replyPreviewPreservesParagraphsAndBullets()
	{
		let summary = ConversationTurnSummary.make(from: [
			entry(
				"turn:request",
				.user,
				"Request"
			),
			entry(
				"turn:reply",
				.agent,
				"Implemented changes:\n\n- **First** change\n- Second change"
			),
		])[0]
		#expect(summary.reply == "Implemented changes:\n\n• First change\n• Second change")
	}

	@Test func compactPreviewUsesAllThreeLinesForContent() throws
	{
		_ = NSApplication.shared
		let summary = ConversationTurnSummary.make(from: [
			entry(
				"turn:request",
				.user,
				"Task names in CodexGUI under project tabs"
			),
			entry(
				"turn:reply",
				.agent,
				"Implemented all six sidebar changes:\n\n"
					+ "- Reduced task indentation.\n"
					+ "- Added distinct expanded/collapsed project icons.\n"
					+ "- Fixed ellipsis truncation."
			),
		])[0]
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: false
		)
		let stack = try #require(preview.subviews.first as? NSStackView)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		#expect(!reply.stringValue.contains("\n\n"))
		#expect(reply.stringValue.contains("• Reduced task indentation."))
		#expect(reply.stringValue.contains("• Added distinct"))
		#expect(reply.stringValue.hasSuffix("…"))
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
