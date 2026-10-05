import Foundation

protocol ConversationPreviewPreparing: Sendable
{
	func prepare(_ turn: CodexTurn) throws -> ConversationTurnPreview
}

/// The runtime supplies the feature's Markdown renderer at application composition.
struct ConversationTextPreviewPreparer: ConversationPreviewPreparing
{
	func prepare(_ turn: CodexTurn) throws -> ConversationTurnPreview
	{
		try ConversationTurnPreviewPreparation.prepare(turn)
		{
			$0
		}
	}
}

enum ConversationTurnPreviewPreparation
{
	static func prepare(
		_ turn: CodexTurn,
		renderReply: (String) -> String
	) throws -> ConversationTurnPreview
	{
		try Task.checkCancellation()
		var request: CodexItem?
		var reply: String?
		for item in turn.items
		{
			try Task.checkCancellation()
			if item.type == "userMessage", request == nil
			{
				request = item
			}
			else if item.type == "agentMessage", request != nil
			{
				reply = item.text ?? ""
			}
		}
		guard let request
		else
		{
			return ConversationTurnPreview(
				turnID: turn.id,
				entryID: turn.id + ":reference",
				title: "Turn",
				reply: "No text preview is available."
			)
		}
		let title = String(UserMessagePresenter.body(for: request).prefix(400))
			.split(whereSeparator: \.isWhitespace).joined(separator: " ")
		let renderedReply = reply.map
		{
			renderReply(String($0.prefix(400)))
		} ?? ""
		try Task.checkCancellation()
		return ConversationTurnPreview(
			turnID: turn.id,
			entryID: turn.id + ":" + request.id,
			title: String(title.prefix(160)),
			reply: String(renderedReply.prefix(800))
		)
	}
}
