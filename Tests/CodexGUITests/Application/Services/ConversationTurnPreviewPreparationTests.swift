import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationTurnPreviewPreparationTests
{
	@Test func firstRequestAndFinalReplyArePreparedWithoutTranscriptEntries() throws
	{
		let turn = makeTurn(items: [
			message(
				"before",
				type: "agentMessage",
				text: "Earlier commentary"
			),
			request(
				"request",
				text: "  First\n\trequest  "
			),
			message(
				"commentary",
				type: "agentMessage",
				text: "Working"
			),
			request(
				"follow-up",
				text: "Second request"
			),
			message(
				"reply",
				type: "agentMessage",
				text: "**Final** reply"
			)
		])
		var rendered: [String] = []
		let preview = try ConversationTurnPreviewPreparation.prepare(turn)
		{
			rendered.append($0)
			return $0.replacingOccurrences(
				of: "**",
				with: ""
			)
		}
		#expect(preview == ConversationTurnPreview(
			turnID: "turn",
			entryID: "turn:request",
			title: "First request",
			reply: "Final reply"
		))
		#expect(rendered == ["**Final** reply"])
	}

	@Test func compactPreviewRetainsBoundedSourceForLabeledWebLinks() throws
	{
		let source = "See [documentation](https://example.org/guide)."
		let turn = makeTurn(items: [
			request(
				"request",
				text: "Find docs"
			),
			message(
				"reply",
				type: "agentMessage",
				text: source
			),
		])
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

	@Test func preparationBoundsTheInputPassedToReplyRenderingAndRetainedText() throws
	{
		let turn = makeTurn(items: [
			request(
				"request",
				text: String(
					repeating: "é",
					count: 500
				)
			),
			message(
				"reply",
				type: "agentMessage",
				text: String(
					repeating: "🌿",
					count: 500
				)
			)
		])
		var input = ""
		let preview = try ConversationTurnPreviewPreparation.prepare(turn)
		{
			input = $0
			return String(
				repeating: "rendered",
				count: 200
			)
		}
		#expect(input == String(
			repeating: "🌿",
			count: 400
		))
		#expect(preview.title == String(
			repeating: "é",
			count: 160
		))
		#expect(preview.reply.count == 800)
	}

	@Test func imageOnlyRequestUsesAttachmentTitleAndOrdinaryReply() throws
	{
		let imageOnly = CodexItem(json: [
			"id": "request",
			"type": "userMessage",
			"content": [["type": "localImage", "path": "/tmp/image.png"]]
		])!
		let preview = try ConversationTextPreviewPreparer().prepare(makeTurn(items: [
			imageOnly,
			message(
				"reply",
				type: "agentMessage",
				text: "An image description"
			)
		]))
		#expect(preview.entryID == "turn:request")
		#expect(preview.title == "Attached image: image.png")
		#expect(preview.reply == "An image description")
	}

	@Test func missingRequestUsesExistingFallbackWithoutRenderingCommentary() throws
	{
		let preview = try ConversationTurnPreviewPreparation.prepare(makeTurn(items: [
			message(
				"commentary",
				type: "agentMessage",
				text: "Earlier commentary"
			)
		]))
		{
			Issue.record("A turn without a request must not render agent commentary")
			return $0
		}
		#expect(preview.entryID == "turn:reference")
		#expect(preview.title == "Turn")
		#expect(preview.reply == "No text preview is available.")
	}

	@Test func requestWithoutReplyKeepsTheReplyEmpty() throws
	{
		let preview = try ConversationTextPreviewPreparer().prepare(makeTurn(items: [
			request(
				"request",
				text: "A request"
			)
		]))
		#expect(preview.title == "A request")
		#expect(preview.reply.isEmpty)
	}

	@Test func cancelledPreparationReturnsNoCompactPreview() async
	{
		let turn = makeTurn(items: [request(
			"request",
			text: "A request"
		)])
		let task = Task
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			return try ConversationTextPreviewPreparer().prepare(turn)
		}
		do
		{
			_ = try await task.value
			Issue.record("Cancelled preparation should throw")
		}
		catch is CancellationError
		{
		}
		catch
		{
			Issue.record("Unexpected preparation error: \(error)")
		}
	}

	private func request(
		_ id: String,
		text: String
	) -> CodexItem
	{
		CodexItem(json: [
			"id": id,
			"type": "userMessage",
			"content": [["type": "text", "text": text]]
		])!
	}

	private func message(
		_ id: String,
		type: String,
		text: String
	) -> CodexItem
	{
		CodexItem(json: ["id": id, "type": type, "text": text])!
	}

	private func makeTurn(items: [CodexItem]) -> CodexTurn
	{
		CodexTurn(
			id: "turn",
			status: "completed",
			items: items,
			error: nil
		)
	}
}
