import Foundation

/// Task transitions do not require transcript, composer, review, or workspace-choice preparation.
struct TaskNotificationPresentation
{
	let executionState: ExecutionState
	let activeThreadID: String?
	let taskOutcomeUncertain: Bool
	let threads: [ThreadSummary]
	let projectPath: String?
	let workspaceOwner: WorkspaceLifecycleOwnerReference?

	init(
		model: WorkspaceModel,
		owner: WorkspaceLifecycleOwnerReference
	)
	{
		self.init(
			model: model,
			execution: model.execution,
			owner: owner
		)
	}

	init(
		model: WorkspaceModel,
		execution: ExecutionModel,
		owner: WorkspaceLifecycleOwnerReference
	)
	{
		executionState = execution.state
		activeThreadID = execution.activeThreadID ?? execution.owner?.submission.threadID
		taskOutcomeUncertain = execution.needsReconciliation
			|| execution.hasUncertainRequest
			|| model.lifecycle.managedOwnershipConflict != nil
		threads = model.conversations.threads
		projectPath = model.identity.canonicalCheckoutPath
		workspaceOwner = owner
	}

	init(snapshot: ConversationSnapshot)
	{
		executionState = snapshot.activeExecutionState ?? snapshot.executionState
		activeThreadID = snapshot.activeThreadID
		taskOutcomeUncertain = snapshot.taskOutcomeUncertain
		threads = snapshot.threads
		projectPath = snapshot.projectPath
		workspaceOwner = snapshot.workspaceOwner
	}
}
