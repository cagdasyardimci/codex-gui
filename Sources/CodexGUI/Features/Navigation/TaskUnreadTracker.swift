import Foundation

/// Keeps completed results unread until their chat is opened within this navigation session.
struct TaskUnreadTracker
{
	private struct Scope: Hashable
	{
		let runtimeOwner: WorkspaceLifecycleOwnerReference?
		let storeIdentity: String?
		let projectPath: String?
	}

	private struct ReadState
	{
		var unread: Set<String> = []
		var completedThreadID: String?
	}

	private var states: [Scope: ReadState] = [:]

	mutating func observe(_ snapshot: NavigationPresentation) -> Set<String>
	{
		let scope = Scope(
			runtimeOwner: snapshot.owner.runtimeOwner,
			storeIdentity: snapshot.owner.storeIdentity,
			projectPath: snapshot.projectPath
		)
		var state = states[scope, default: ReadState()]
		if let threadID = snapshot.activeThreadID
		{
			if snapshot.activeExecutionState == .completed && !snapshot.taskOutcomeUncertain
			{
				if state.completedThreadID != threadID
				{
					state.unread.insert(threadID)
					state.completedThreadID = threadID
				}
			}
			else if snapshot.activeExecutionState?.isBusy == true
			{
				state.unread.remove(threadID)
				state.completedThreadID = nil
			}
		}
		if let selectedThreadID = snapshot.selectedThreadID
		{
			state.unread.remove(selectedThreadID)
		}
		states[scope] = state
		return state.unread
	}
}
