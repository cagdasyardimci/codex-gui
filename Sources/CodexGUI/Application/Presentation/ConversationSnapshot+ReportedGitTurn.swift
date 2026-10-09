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

	func runningGitReviewRequest(owner: FeaturePresentationOwner) -> GitComparisonRequest?
	{
		guard executionState.isBusy, let threadID = activeThreadID,
				threadID == selectedThreadID, let turnID = activeTurnID
		else
		{
			return nil
		}
		// Only the badge may reuse this task's latest edits while the active turn has no reports.
		let activeChanges = visibleGitReviewTurn.changes
		let previous = activeChanges == nil ? lastReportedGitTurn : nil
		let previousChanges = previous?.changes
		return GitComparisonRequest(
			owner: owner,
			repositoryRoot: owner.runtimeOwner?.workspace.canonicalCheckoutPath
				?? projectPath ?? "",
			scope: .lastTurn,
			generation: 0,
			lastTurnID: previousChanges != nil ? previous?.id : turnID,
			reportedChanges: activeChanges ?? previousChanges
		)
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
