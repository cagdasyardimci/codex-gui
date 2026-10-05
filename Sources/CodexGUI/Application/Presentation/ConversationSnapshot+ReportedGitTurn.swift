import Foundation

extension ConversationSnapshot
{
	/// A later reply or commit-only turn does not replace the latest recorded editing turn.
	var lastReportedGitTurn: (id: String, changes: [FileChange]?)?
	{
		guard let reportedGitTurnID
		else
		{
			return nil
		}
		return (reportedGitTurnID, reportedGitChanges)
	}
}
