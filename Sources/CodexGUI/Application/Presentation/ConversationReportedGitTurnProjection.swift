import Foundation

/// Editing-turn identity survives eviction; missing payloads stay unavailable.
struct ConversationReportedGitTurnProjection
{
	let turnID: String?
	let changes: [FileChange]?

	init(content: ConversationContentModel)
	{
		turnID = content.latestReportedGitTurn?.id
		guard let turnID
		else
		{
			changes = nil
			return
		}
		if let turn = content.loadedTurns.first(where:
			{
				$0.id == turnID
			})
		{
			guard turn.itemsAreComplete
			else
			{
				changes = nil
				return
			}
			var seen: Set<String> = []
			let reportedItems = turn.items.reversed().filter
			{
				seen.insert($0.id).inserted
			}
			.reversed().filter
			{
				$0.type == "fileChange" && $0.status == "completed"
			}
			if !reportedItems.isEmpty
			{
				changes = reportedItems.flatMap(\.changes)
				return
			}
		}
		// Live item completions can precede publication of the canonical turn body.
		let prefix = turnID + ":"
		let reportedEntries = content.entries.filter
		{
			guard $0.id.hasPrefix(prefix), case .fileChanges(
				_,
				let status
			) = $0.activity
			else
			{
				return false
			}
			return status == "completed"
		}
		guard !reportedEntries.isEmpty
		else
		{
			changes = nil
			return
		}
		var seen: Set<String> = []
		changes = reportedEntries.reversed().filter
		{
			seen.insert($0.id).inserted
		}
		.reversed().flatMap
		{
			entry -> [FileChange] in
			if case .fileChanges(
				let changes,
				_
			) = entry.activity
			{
				return changes
			}
			return []
		}
	}
}
