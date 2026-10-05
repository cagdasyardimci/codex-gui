import Foundation

extension ConversationSnapshot
{
	/// A later reply or commit-only turn does not replace the latest recorded editing turn.
	var lastReportedGitTurn: (id: String, changes: [FileChange])?
	{
		guard let last = entries.last(where:
			{
				entry in
				if case .fileChanges(
					_,
					let status
				) = entry.activity
				{
					return status == "completed"
				}
				return false
			})
		else
		{
			return nil
		}
		let turnID = last.id.components(separatedBy: ":").first ?? last.id
		let changes = entries.flatMap
		{
			entry -> [FileChange] in
			guard entry.id.components(separatedBy: ":").first == turnID,
					case .fileChanges(
					let changes,
					let status
					) = entry.activity, status == "completed"
			else
			{
				return []
			}
			return changes
		}
		return (turnID, changes)
	}
}
