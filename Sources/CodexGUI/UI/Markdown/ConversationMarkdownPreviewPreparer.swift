import Foundation

/// Prepares canonical previews with the transcript's Markdown-to-plain-text semantics.
struct ConversationMarkdownPreviewPreparer: ConversationPreviewPreparing
{
	func prepare(_ turn: CodexTurn) throws -> ConversationTurnPreview
	{
		try ConversationTurnPreviewPreparation.prepare(
			turn,
			renderReply:
			{
				excerpt in
				MarkdownPlainTextRenderer.render(MarkdownContentParser.parse(
					excerpt,
					markdown: true
				))
			}
		)
	}
}
