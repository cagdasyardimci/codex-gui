import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnSummaryPreviewTests
{
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

}
