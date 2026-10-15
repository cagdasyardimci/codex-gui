import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationMarkdownPreviewPreparerTests
{
	@Test func compactPreviewRetainsBoundedSourceForLabeledWebLinks() throws
	{
		let source = "See [documentation](https://example.org/guide)."
		let turn = CodexTurn(
			id: "turn",
			status: "completed",
			items: [
				CodexItem(json: [
					"id": "request",
					"type": "userMessage",
					"content": [["type": "text", "text": "Find docs"]]
				])!,
				CodexItem(json: ["id": "reply", "type": "agentMessage", "text": source])!,
			],
			error: nil
		)
		let preview = try ConversationMarkdownPreviewPreparer().prepare(turn)
		#expect(preview.reply == "See documentation.")
		#expect(preview.replySource == source)
		#expect(ConversationCachePolicy.cost(preview) > ConversationCachePolicy.cost(
			ConversationTurnPreview(
				turnID: preview.turnID,
				entryID: preview.entryID,
				title: preview.title,
				reply: preview.reply
			)
		))
	}
}
