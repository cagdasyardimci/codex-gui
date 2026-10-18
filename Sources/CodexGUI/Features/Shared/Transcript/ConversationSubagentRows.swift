import Foundation

enum ConversationSubagentRows
{
	static func row(
		id: String,
		agents: [CodexSubagentActivity]
	) -> ConversationActivityRow
	{
		let title: String
		if agents.count > 2
		{
			title = "\(agents[0].name), \(agents[1].name) and \(agents.count - 2) more"
		}
		else
		{
			title = agents.map(\.name).joined(separator: " and ")
		}
		return ConversationActivityRow(
			id: id,
			sourceEntryID: id,
			groupID: id,
			kind: .subagent,
			title: "\(title) \(agents.first?.action ?? "activity")",
			subagents: agents
		)
	}

	static func group(_ rows: [ConversationTranscriptRow]) -> [ConversationTranscriptRow]
	{
		var result: [ConversationTranscriptRow] = []
		var start = 0
		while start < rows.count
		{
			guard case .activity(let first) = rows[start], first.kind == .subagent
			else
			{
				result.append(rows[start])
				start += 1
				continue
			}
			let turnID = ConversationEntryIdentity.turnIDWithFallback(first.id)
			var end = start + 1
			while end < rows.count, case .activity(let next) = rows[end],
					next.kind == .subagent,
					next.subagents.first?.kind == first.subagents.first?.kind,
					ConversationEntryIdentity.turnIDWithFallback(next.id) == turnID
			{
				end += 1
			}
			if end == start + 1
			{
				result.append(rows[start])
			}
			else
			{
				var agents = first.subagents
				for index in start + 1 ..< end
				{
					if case .activity(let next) = rows[index]
					{
						agents.append(contentsOf: next.subagents)
					}
				}
				result.append(.activity(row(
					id: first.id,
					agents: agents
				)))
			}
			start = end
		}
		return result
	}
}
