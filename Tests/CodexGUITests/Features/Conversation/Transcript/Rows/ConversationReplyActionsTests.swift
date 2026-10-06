import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationReplyActionsTests
{
	@Test func copyingPreservesCurrentMarkdownAndExactUnicode() throws
	{
		_ = NSApplication.shared
		let actions = ConversationReplyActionsView()
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		actions.configure(
			source: "Old response",
			bookmarked: false,
			onToggleBookmark: nil
		)
		let source = "**cafe\u{0301} 😀**\n\n```text\n  exact\tspacing  \n```"
		actions.configure(
			source: source,
			bookmarked: false,
			onToggleBookmark: nil
		)
		actions.writeResponse(to: pasteboard)
		let copied = try #require(pasteboard.string(forType: .string))
		#expect(copied.utf8.elementsEqual(source.utf8))
		let copy = try #require(button(
			in: actions,
			label: "Copy response"
		))
		#expect(copy.isEnabled)
		#expect(copy.target === actions)
		#expect(copy.action == NSSelectorFromString("copyResponse"))
	}

	@Test func bookmarkReflectsCurrentStateAndResetDisconnectsOldActions() throws
	{
		_ = NSApplication.shared
		let actions = ConversationReplyActionsView()
		var firstToggles = 0
		var nextToggles = 0
		actions.configure(
			source: "First response",
			bookmarked: false,
			onToggleBookmark:
			{
				firstToggles += 1
			}
		)
		let bookmark = try #require(button(
			in: actions,
			label: "Bookmark turn"
		))
		bookmark.performClick(nil)
		#expect(firstToggles == 1)
		actions.configure(
			source: "Next response",
			bookmarked: true,
			onToggleBookmark:
			{
				nextToggles += 1
			}
		)
		#expect(bookmark.accessibilityLabel() == "Remove turn bookmark")
		bookmark.performClick(nil)
		#expect(firstToggles == 1 && nextToggles == 1)
		actions.setBookmarked(false)
		#expect(bookmark.accessibilityLabel() == "Bookmark turn")
		actions.reset()
		#expect(actions.isHidden)
		#expect(!bookmark.isEnabled && bookmark.target == nil && bookmark.action == nil)
		bookmark.performClick(nil)
		#expect(firstToggles == 1 && nextToggles == 1)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		pasteboard.setString(
			"Keep current pasteboard",
			forType: .string
		)
		actions.writeResponse(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == "Keep current pasteboard")
	}

	@Test func bookmarkIsHiddenWhenNoSupportedCallbackExists() throws
	{
		let actions = ConversationReplyActionsView()
		actions.configure(
			source: "Response",
			bookmarked: false,
			onToggleBookmark: nil
		)
		let bookmark = try #require(button(
			in: actions,
			label: "Bookmark turn"
		))
		#expect(bookmark.isHidden)
		#expect(!bookmark.isEnabled && bookmark.target == nil && bookmark.action == nil)
	}

	@Test func actionsBelongOnlyToNewestTerminalReply()
	{
		let first = [
			entry(
				"first:request",
				kind: .user
			),
			entry("first:reply"),
		]
		let second = [
			entry(
				"second:request",
				kind: .user
			),
			entry("second:commentary"),
			entry("second:reply"),
			entry(
				"second:changes",
				kind: .tool
			),
			entry(
				"notice",
				kind: .notice
			),
		]
		let completed = ConversationTurnTiming(
			turnID: "first",
			status: "completed"
		)
		#expect(ConversationReplyActionsView.replyEntryID(
			in: first,
			timings: [completed]
		) == "first:reply")
		for status in ["inProgress", "statusUnknown"]
		{
			#expect(ConversationReplyActionsView.replyEntryID(
				in: first + second,
				timings: [completed, ConversationTurnTiming(
					turnID: "second",
					status: status
				)]
			) == nil)
		}
		for status in ["completed", "failed", "interrupted", "stopped", "cancelled"]
		{
			#expect(ConversationReplyActionsView.replyEntryID(
				in: first + second,
				timings: [completed, ConversationTurnTiming(
					turnID: "second",
					status: status
				)]
			) == "second:reply")
		}
		#expect(ConversationReplyActionsView.replyEntryID(
			in: first + [entry(
				"second:request",
				kind: .user
			)],
			timings: [completed]
		) == nil)
		#expect(ConversationReplyActionsView.replyEntryID(
			in: first,
			timings: []
		) == nil)
	}

	@Test func collectionReuseHidesActionsAndClearsReplyOwnership() throws
	{
		_ = NSApplication.shared
		let item = ConversationCollectionItem()
		configure(
			item,
			entry: entry("first:reply"),
			showsReplyActions: true
		)
		let actions = try #require(find(
			ConversationReplyActionsView.self,
			in: item.view
		))
		let copy = try #require(button(
			in: actions,
			label: "Copy response"
		))
		#expect(!actions.isHiddenOrHasHiddenAncestor)
		item.prepareForReuse()
		#expect(actions.isHiddenOrHasHiddenAncestor)
		#expect(copy.target == nil && copy.action == nil)
		configure(
			item,
			entry: entry(
				"second:request",
				kind: .user
			),
			showsReplyActions: true
		)
		#expect(actions.superview == nil)
		#expect(!copy.isEnabled)
		configure(
			item,
			entry: entry("second:reply"),
			showsReplyActions: false
		)
		#expect(actions.superview == nil)
		#expect(copy.target == nil && copy.action == nil)
	}

	@Test func measuredActionsKeepBodyGeometryAndFitBelowTextAtBothWidths() throws
	{
		_ = NSApplication.shared
		let reply = entry(
			"turn:reply",
			body: "First paragraph.\n\n- One\n- Two"
		)
		let content = PreparedConversationContent(ConversationContentParser.parse(
			reply.body,
			markdown: true
		))
		let item = ConversationCollectionItem()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 736,
				height: 200
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = item
		defer
		{
			window.contentViewController = nil
			window.close()
		}
		for width: CGFloat in [220, 736]
		{
			item.configure(
				reply,
				content: content,
				expanded: false,
				onToggle:
				{
				}
			)
			let bodySize = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false
			)
			window.setContentSize(bodySize)
			item.view.layoutSubtreeIfNeeded()
			let text = try #require(find(
				NSTextView.self,
				in: item.view
			))
			let bodyFrame = item.view.convert(
				text.bounds,
				from: text
			)
			let bodyTop = item.view.bounds.maxY - bodyFrame.maxY
			item.configure(
				reply,
				content: content,
				expanded: false,
				showsReplyActions: true,
				onToggle:
				{
				}
			)
			let actionSize = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false,
				showsReplyActions: true
			)
			window.setContentSize(actionSize)
			item.view.layoutSubtreeIfNeeded()
			let actions = try #require(find(
				ConversationReplyActionsView.self,
				in: item.view
			))
			let nextBodyFrame = item.view.convert(
				text.bounds,
				from: text
			)
			let actionFrame = item.view.convert(
				actions.bounds,
				from: actions
			)
			#expect(actionSize.height - bodySize.height == 28.5)
			#expect(nextBodyFrame.size == bodyFrame.size)
			#expect(item.view.bounds.maxY - nextBodyFrame.maxY == bodyTop)
			#expect(abs(nextBodyFrame.minY - actionFrame.maxY - 8.5) < 0.5)
			#expect(actionFrame.height == ConversationReplyActionsView.height)
			#expect(item.view.bounds.contains(actionFrame))
			#expect(ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false
			) == bodySize)
			item.configure(
				reply,
				content: content,
				expanded: false,
				onToggle:
				{
				}
			)
			window.setContentSize(bodySize)
			item.view.layoutSubtreeIfNeeded()
			#expect(actions.superview == nil)
			let stack = try #require(text.superview as? NSStackView)
			#expect(stack.customSpacing(after: text) == 6)
			#expect(item.view.convert(
				text.bounds,
				from: text
			) == bodyFrame)
		}
	}

	private func entry(
		_ id: String,
		kind: ConversationEntryKind = .agent,
		body: String = "Response"
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: kind == .agent ? "Codex" : "User",
			body: body
		)
	}

	private func configure(
		_ item: ConversationCollectionItem,
		entry: ConversationEntry,
		showsReplyActions: Bool
	)
	{
		item.configure(
			entry,
			content: PreparedConversationContent(ConversationContentParser.parse(
				entry.body,
				markdown: true
			)),
			expanded: false,
			showsReplyActions: showsReplyActions,
			onToggle:
			{
			}
		)
	}

	private func button(
		in view: NSView,
		label: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				in: $0,
				label: label
			)
		}.first
	}

	private func find<View: NSView>(
		_ type: View.Type,
		in view: NSView
	) -> View?
	{
		if let result = view as? View
		{
			return result
		}
		return view.subviews.lazy.compactMap
		{
			find(
				type,
				in: $0
			)
		}.first
	}
}
