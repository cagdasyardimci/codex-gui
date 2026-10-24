import Foundation

struct NavigationPresentation: Equatable
{
	let owner: FeaturePresentationOwner
	let projectPath: String?
	let threads: [ThreadSummary]
	let sidebarThreads: [ThreadSummary]?
	let sidebarListLoading: Bool
	let sidebarListError: String?
	let sidebarConnectionGeneration: Int?
	let selectedThreadID: String?
	let executionState: ExecutionState
	let activeThreadID: String?
	let activeExecutionState: ExecutionState?
	let taskOutcomeUncertain: Bool
	let threadExecutions: [String: ThreadExecutionPresentation]
	let activeExecutionCount: Int?
	let showingArchived: Bool
	let canManageThreads: Bool
	let threadManagementAvailability: [String: Bool]?
	let recentProjects: [URL]
	let pinnedProjectPaths: Set<String>
	let removedProjectPaths: Set<String>
	let pinnedTasks: [ThreadSummary]
	let projectDisplayNames: [String: String]
	let taskWorkspaces: [TaskWorkspaceChoice]
	let selectedTaskWorkspaceID: UUID?
	let taskStatusSummary: String?
	let taskWorkspaceMessage: String?
	let draftLifetime: Int

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: ownerIdentity
		)
		projectPath = snapshot.projectPath
		threads = snapshot.threads
		sidebarThreads = snapshot.sidebarThreads
		sidebarListLoading = snapshot.sidebarListLoading
		sidebarListError = snapshot.sidebarListError
		sidebarConnectionGeneration = snapshot.sidebarConnectionGeneration
		selectedThreadID = snapshot.selectedThreadID
		executionState = snapshot.executionState
		activeThreadID = snapshot.activeThreadID
		activeExecutionState = snapshot.activeExecutionState
		taskOutcomeUncertain = snapshot.taskOutcomeUncertain
		activeExecutionCount = snapshot.activeExecutionCount
		if snapshot.threadExecutions.isEmpty, let threadID = snapshot.activeThreadID,
			let state = snapshot.activeExecutionState
		{
			threadExecutions = [threadID: ThreadExecutionPresentation(
				state: state,
				outcomeUncertain: snapshot.taskOutcomeUncertain
			)]
		}
		else
		{
			threadExecutions = snapshot.threadExecutions
		}
		showingArchived = snapshot.showingArchived
		canManageThreads = snapshot.canManageThreads
		threadManagementAvailability = snapshot.threadManagementAvailability
		recentProjects = snapshot.recentProjects
		pinnedProjectPaths = snapshot.pinnedProjectPaths
		removedProjectPaths = snapshot.removedProjectPaths
		pinnedTasks = snapshot.pinnedTasks
		projectDisplayNames = snapshot.projectDisplayNames
		taskWorkspaces = snapshot.taskWorkspaces
		selectedTaskWorkspaceID = snapshot.selectedTaskWorkspaceID
		taskStatusSummary = snapshot.taskStatusSummary
		taskWorkspaceMessage = snapshot.taskWorkspaceMessage
		draftLifetime = snapshot.composerDraftLifetime
	}
}
