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
			var reportedChanges: [FileChange] = []
			var hasReportedItems = false
			for item in turn.items.reversed()
			{
				guard seen.insert(item.id).inserted,
						item.type == "fileChange", item.status == "completed"
				else
				{
					continue
				}
				hasReportedItems = true
				reportedChanges.append(contentsOf: item.changes.reversed())
			}
			if hasReportedItems
			{
				reportedChanges.reverse()
				changes = reportedChanges
				return
			}
		}
		// Live item completions can precede publication of the canonical turn body.
		let prefix = turnID + ":"
		var seen: Set<String> = []
		var reportedChanges: [FileChange] = []
		var hasReportedEntries = false
		for entry in content.entries.reversed()
		{
			guard entry.id.hasPrefix(prefix), case .fileChanges(
				let entryChanges,
				let status
			) = entry.activity, status == "completed", seen.insert(entry.id).inserted
			else
			{
				continue
			}
			hasReportedEntries = true
			reportedChanges.append(contentsOf: entryChanges.reversed())
		}
		if hasReportedEntries
		{
			reportedChanges.reverse()
			changes = reportedChanges
		}
		else
		{
			changes = nil
		}
	}
}
