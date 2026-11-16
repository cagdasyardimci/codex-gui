import Foundation
import Testing

@testable import CodexGUI

@Suite
struct UserMessagePresenterTests
{
	@Test @MainActor func questionReplyEnvelopesPresentAnswersAcrossHistoryAndPreviews() throws
	{
		let text = try questionEnvelope([
			["questionItemId": "[\"request_user_input_async\",\"call_first\",0]",
				"question": "Which area?",
				"answer": "Chat"],
			["questionItemId": "[\"request_user_input_async\",\"call_first\",1]",
				"question": "What should improve?",
				"answer": "Lag\nKeep selection."],
		])
		let item = try #require(CodexItem(json: [
			"id": "reply",
			"type": "userMessage",
			"content": [["type": "text", "text": text]]
		]))
		let entry = ConversationContentReducer.entry(
			for: item,
			id: "turn:reply"
		)
		let expected = "Which area?\nChat\n\nWhat should improve?\nLag\nKeep selection."
		#expect(entry.body == expected)
		#expect(entry.questionPrompts == ["Which area?", "What should improve?"])
		#expect(UserMessagePresenter.body(for: [.text(text)]) == expected)
		#expect(UserMessagePresenter.previewRequest(in: text) == expected)
		#expect(item.text == text)
	}

	@Test func incompleteOrQuotedQuestionRepliesRemainLiteral() throws
	{
		let valid = try questionEnvelope([
			["questionItemId": "call:0", "question": "Which area?", "answer": "Chat"],
		])
		let cases = [
			"Explain this:\n" + valid,
			"```json\n" + valid + "\n```",
			valid + "\nKeep this trailing text.",
			String(valid.dropLast(10)),
			"<send_user_message_question_reply>not JSON</send_user_message_question_reply>",
			"<send_user_message_question_reply>[]</send_user_message_question_reply>",
			try questionEnvelope([["question": "Which area?", "answer": "Chat"]]),
			try questionEnvelope([[
				"questionItemId": "call:0",
				"question": "Which area?",
				"answer": 3
			]]),
			try questionEnvelope([
				["questionItemId": "call:0", "question": "Which area?", "answer": "Chat"],
				["questionItemId": "call:1", "question": "Missing answer"],
			]),
		]
		for text in cases
		{
			let item = try #require(CodexItem(json: [
				"id": "literal",
				"type": "userMessage",
				"content": [["type": "text", "text": text]]
			]))
			#expect(UserMessagePresenter.body(for: item) == text)
			#expect(UserMessagePresenter.questionPrompts(for: item).isEmpty)
			#expect(UserMessagePresenter.previewRequest(in: text) == text)
		}
	}

	private func questionEnvelope(_ replies: [[String: Any]]) throws -> String
	{
		let data = try JSONSerialization.data(withJSONObject: replies)
		return "<send_user_message_question_reply>\n"
			+ String(
				decoding: data,
				as: UTF8.self
			)
			+ "\n</send_user_message_question_reply>"
	}

	@Test @MainActor func attachmentTitlesAgreeAcrossInputLoadedAndCompactPreviews() throws
	{
		let cases: [(String, [String], String)] = [
			(
				"Attached image: Pasted image",
				["/tmp/paste.png"],
				"Attached image: Pasted image"
			),
			(
				"",
				["/tmp/first.png", "/tmp/second.png"],
				"Attached image: first.png; Attached image: second.png"
			),
			(
				"Attached image: First\n\nAttached image: Second",
				["/tmp/first.png", "/tmp/second.png"],
				"Attached image: First; Attached image: Second"
			),
			("  \n", ["data:image/png;base64,AAAA"], "Attached image"),
			("Inspect this\n\nAttached image: Pasted image", ["/tmp/paste.png"], "Inspect this"),
			(
				"Discuss the sentence:\nAttached image: example\nKeep this sentence.",
				["/tmp/paste.png"],
				"Discuss the sentence: Attached image: example Keep this sentence."
			),
		]
		for (text, paths, expected) in cases
		{
			let inputs: [TurnInput] = [.text(text)] + paths.map
			{
				.localImage(path: $0)
			}
			let content: [[String: Any]] = [["type": "text", "text": text]]
				+ paths.map
				{
					["type": "localImage", "path": $0]
				}
			let item = try #require(CodexItem(json: [
				"id": "request",
				"type": "userMessage",
				"content": content
			]))
			let entry = ConversationContentReducer.entry(
				for: item,
				id: "turn:request"
			)
			let loaded = try #require(ConversationTurnSummary.make(from: [entry]).first)
			let compact = try ConversationTextPreviewPreparer().prepare(CodexTurn(
				id: "turn",
				status: "completed",
				items: [item],
				error: nil
			))
			#expect(loaded.title == expected)
			#expect(compact.title == expected)
			#expect(entry.attachmentPreviewTitle
				== UserMessagePresenter.attachmentPreviewTitle(for: inputs))
			#expect(entry.body == UserMessagePresenter.body(for: inputs))
			if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				|| text.hasPrefix("Attached image:")
			{
				#expect(entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
		}
	}

	@Test func presenterRetainsReferencesWithoutMatchingDescriptions()
	{
		let inputs: [TurnInput] = [
			.text("File reference: Other.swift\nAttached image: First screenshot"),
			.mention(
				name: "Example.swift",
				path: "/tmp/Example.swift"
			),
			.localImage(path: "/tmp/first.png"),
			.localImage(path: "/tmp/second.png"),
		]
		let body = UserMessagePresenter.body(for: inputs)
		#expect(body.contains("[File reference: Example.swift]"))
		#expect(!body.contains("[Image: first.png]"))
		#expect(!body.contains("[Image: second.png]"))
		#expect(!body.contains("Attached image:"))
		#expect(UserMessagePresenter.imageAttachments(for: inputs).map(\.path) == [
			"/tmp/first.png",
			"/tmp/second.png"
		])
	}

	@Test func referenceProjectionPrefersWireLabelsAndPreservesByteDistinctPaths() throws
	{
		let text = "# Files mentioned by the user:\n\n"
			+ "## Generated.png: /tmp/image.png\nImage attachment: true\n\n"
			+ "## Guide.md: /tmp/Guide.md\n\n## My request:\nRead these."
		let inputs: [TurnInput] = [
			.text(text),
			.localImage(path: "file:///tmp/image.png"),
			.mention(
				name: "Wire guide",
				path: "/tmp/Guide.md"
			),
			.mention(
				name: "Composed",
				path: "/tmp/é.md"
			),
			.mention(
				name: "Decomposed",
				path: "/tmp/e\u{301}.md"
			),
		]
		let references = UserMessagePresenter.sourceReferences(for: inputs)
		#expect(references.map(\.name) == ["image.png", "Wire guide", "Composed", "Decomposed"])
		#expect(references.count == 4)
		#expect(Set(references.map
			{
				Data($0.path.utf8)
			}).count == 4)
		#expect(UserMessagePresenter.imageAttachments(for: inputs).count == 1)
		let entry = ConversationEntry(
			id: "turn:references",
			kind: .user,
			title: "You",
			body: "Read these.",
			sourceReferences: references
		)
		let sources = ConversationLocalSources(entries: [entry])
		#expect(sources.records.count == 4)
		#expect(sources.records.map(\.name) == references.map(\.name))
		#expect(UserMessagePresenter.body(for: inputs)
			== "Read these.\n[File reference: Wire guide]\n[File reference: Composed]"
			+ "\n[File reference: Decomposed]")
	}

}
