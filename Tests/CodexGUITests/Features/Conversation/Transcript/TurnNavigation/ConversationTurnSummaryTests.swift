import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnSummaryTests
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

	@Test func replyPreviewSeparatesBlocksAndKeepsHardBreaksCodeAndTableText()
	{
		let body = "Intro soft\ncontinuation  \nhard break\n\n"
			+ "- first\n- second\n\n"
			+ "```text\n  exact 😀\n\nnext  \n```\n\n"
			+ "| Name | Value |\n| --- | --- |\n| alpha | 42 |\n\nAfter."
		let summary = ConversationTurnSummary.make(from: [
			entry(
				"turn:request",
				.user,
				"Request"
			),
			entry(
				"turn:reply",
				.agent,
				body
			),
		])[0]
		#expect(summary.reply == "Intro soft continuation\nhard break\n\n"
			+ "• first\n• second\n\n  exact 😀\n\nnext  \n\n"
			+ "Name\nValue\nalpha\n42\n\nAfter.")
	}

	@Test func replyPreviewKeepsQuotedParagraphBoundaryInsideOneListItem()
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
				"- > first\n  >\n  > second"
			),
		])[0]
		#expect(summary.reply.hasPrefix("• "))
		#expect(summary.reply.contains("first\n\nsecond"))
		#expect(!summary.reply.contains("│"))
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
