import Foundation

struct NavigationPresentation: Equatable
{
	let owner: FeaturePresentationOwner
	let projectPath: String?
	let threads: [ThreadSummary]
	let selectedThreadID: String?
	let executionState: ExecutionState
	let activeThreadID: String?
	let activeExecutionState: ExecutionState?
	let showingArchived: Bool
	let canManageThreads: Bool
	let recentProjects: [URL]
	let pinnedProjectPaths: Set<String>
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
		selectedThreadID = snapshot.selectedThreadID
		executionState = snapshot.executionState
		activeThreadID = snapshot.activeThreadID
		activeExecutionState = snapshot.activeExecutionState
		showingArchived = snapshot.showingArchived
		canManageThreads = snapshot.canManageThreads
		recentProjects = snapshot.recentProjects
		pinnedProjectPaths = snapshot.pinnedProjectPaths
		projectDisplayNames = snapshot.projectDisplayNames
		taskWorkspaces = snapshot.taskWorkspaces
		selectedTaskWorkspaceID = snapshot.selectedTaskWorkspaceID
		taskStatusSummary = snapshot.taskStatusSummary
		taskWorkspaceMessage = snapshot.taskWorkspaceMessage
		draftLifetime = snapshot.composerDraftLifetime
	}
}
