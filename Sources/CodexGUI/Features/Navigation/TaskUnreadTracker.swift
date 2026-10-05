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
		var completedThreadIDs: Set<String> = []
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
		for (threadID, execution) in snapshot.threadExecutions
		{
			if execution.state == .completed && !execution.outcomeUncertain
			{
				if state.completedThreadIDs.insert(threadID).inserted
				{
					state.unread.insert(threadID)
				}
			}
			else if execution.state.isBusy
			{
				state.unread.remove(threadID)
				state.completedThreadIDs.remove(threadID)
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
