import Foundation

enum ConversationSubagentRows
{
	static func row(
		id: String,
		agents: [CodexSubagentActivity]
	) -> ConversationActivityRow
	{
		let names = agents.map(\.name)
		let title: String
		if names.count > 2
		{
			title = "\(names[0]), \(names[1]) and \(names.count - 2) more"
		}
		else
		{
			title = names.joined(separator: " and ")
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
		for current in rows
		{
			if case .activity(let next) = current, next.kind == .subagent,
				case .activity(let previous) = result.last, previous.kind == .subagent,
				previous.subagents.first?.kind == next.subagents.first?.kind,
				previous.id.components(separatedBy: ":").first
				== next.id.components(separatedBy: ":").first
			{
				result[result.count - 1] = .activity(row(
					id: previous.id,
					agents: previous.subagents + next.subagents
				))
			}
			else
			{
				result.append(current)
			}
		}
		return result
	}
}
