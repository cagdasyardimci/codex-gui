import Foundation

extension ConversationSnapshot
{
	var visibleGitReviewTurn: (id: String?, changes: [FileChange]?)
	{
		if executionState.isBusy, activeThreadID != nil,
			activeThreadID == selectedThreadID, let activeTurnID
		{
			return (
				activeTurnID,
				reportedGitTurnID == activeTurnID ? reportedGitChanges : nil
			)
		}
		return (lastReportedGitTurn?.id ?? lastGitTurnID, reportedGitChanges)
	}

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
