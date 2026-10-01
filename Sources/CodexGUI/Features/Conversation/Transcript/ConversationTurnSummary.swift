import Foundation

/// A local preview of a loaded turn. No generated summary or backend request is needed.
struct ConversationTurnSummary: Equatable
{
	let turnID: String
	let entryID: String
	let title: String
	var reply: String

	static func make(from entries: [ConversationEntry]) -> [Self]
	{
		var summaries: [Self] = []
		var indices: [String: Int] = [:]
		for entry in entries
		{
			guard let separator = entry.id.firstIndex(of: ":")
			else
			{
				continue
			}
			let turnID = String(entry.id[..<separator])
			if entry.kind == .user, indices[turnID] == nil
			{
				indices[turnID] = summaries.count
				summaries.append(Self(
					turnID: turnID,
					entryID: entry.id,
					title: preview(entry.body),
					reply: ""
				))
			}
			else if entry.kind == .agent, let index = indices[turnID]
			{
				let excerpt = String(entry.body.prefix(400))
				let parsed = ConversationContentParser.parse(
					excerpt,
					markdown: true
				)
				summaries[index].reply = ConversationPlainTextRenderer.render(parsed)
			}
		}
		return summaries
	}

	private static func preview(_ text: String) -> String
	{
		let prefix = String(text.prefix(400))
		return prefix.split(whereSeparator:
			{
				$0.isWhitespace
			}).joined(separator: " ")
	}
}
