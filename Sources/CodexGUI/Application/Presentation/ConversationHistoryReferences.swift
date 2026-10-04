import Foundation

enum ConversationHistoryReferences
{
	static func collect(from turns: [CodexTurn]) -> [UserMessageReference]
	{
		var references: [UserMessageReference] = []
		for turn in turns
		{
			for item in turn.items where item.type == "userMessage"
			{
				references.append(contentsOf: item.references)
			}
		}
		return references
	}
}
