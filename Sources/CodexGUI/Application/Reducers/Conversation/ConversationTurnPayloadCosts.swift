import Foundation

/// Loaded item payloads change separately from provisional streaming text.
struct ConversationTurnPayloadCosts
{
	let turnIDs: [String]
	let byTurn: [String: Int]
	let representedEntryIDs: Set<String>
	let totalBytes: Int

	init(turns: [CodexTurn])
	{
		var byTurn: [String: Int] = [:]
		var represented: Set<String> = []
		var total = 0
		for turn in turns
		{
			let cost = ConversationCachePolicy.cost(turn)
			byTurn[turn.id, default: 0] = ConversationCachePolicy.sum(
				byTurn[turn.id, default: 0],
				cost
			)
			total = ConversationCachePolicy.sum(
				total,
				cost
			)
			for item in turn.items
			{
				represented.insert(turn.id + ":" + item.id)
			}
		}
		turnIDs = turns.map(\.id)
		self.byTurn = byTurn
		representedEntryIDs = represented
		totalBytes = total
	}
}
