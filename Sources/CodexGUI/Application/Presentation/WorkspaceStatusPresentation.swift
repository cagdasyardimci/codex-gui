import Foundation

/// Account and execution chrome do not need transcript or composer values.
struct WorkspaceStatusPresentation: Equatable
{
	let execution: ThreadExecutionPresentation
	let accountDescription: String
	let accountStatus: AccountStatus?
	let accountActionPending: Bool
	let canLogOut: Bool
	let accountActionError: String?
	let backendDescription: String
	let usage: UsagePresentation
	let threadTokenUsage: ThreadTokenUsage?
	let threadStatus: ThreadStatus?
	let threadSettings: ThreadSettings?
	var executionState: ExecutionState
	{
		execution.state
	}

	@MainActor
	init(
		model: WorkspaceModel,
		now: Date
	)
	{
		let selectors = WorkspaceSelectors(
			model: model,
			now: now
		)
		execution = ThreadExecutionPresentation(
			state: selectors.executionState,
			outcomeUncertain: selectors.needsReconciliation || selectors.hasUncertainRequest
		)
		accountDescription = selectors.accountDescription
		accountStatus = model.preferences.accountStatus
		accountActionPending = model.preferences.pendingSignOut != nil
		canLogOut = selectors.isConnected && accountStatus?.type != nil
		accountActionError = model.preferences.signOutError
		backendDescription = selectors.backendDescription
		let id = selectors.selectedThreadID
		threadTokenUsage = id.flatMap
		{
			model.composerCommands.tokenUsage[$0]
		}
		threadStatus = id.flatMap
		{
			model.composerCommands.threadStatuses[$0]
		}
		threadSettings = id.flatMap
		{
			model.composerCommands.threadSettings[$0]
		}
		usage = UsagePresentation(
			limits: model.usage.snapshot,
			refreshedAt: model.usage.fetchedAt,
			isStale: model.usage.isStale(
				isConnected: selectors.isConnected,
				now: now
			),
			unavailableReason: model.usage.error
		)
	}

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		execution = ThreadExecutionPresentation(
			state: snapshot.activeExecutionState ?? snapshot.executionState,
			outcomeUncertain: snapshot.taskOutcomeUncertain
		)
		accountDescription = snapshot.accountDescription
		accountStatus = snapshot.accountStatus
		accountActionPending = snapshot.accountActionPending
		canLogOut = snapshot.canLogOut
		accountActionError = snapshot.accountActionError
		backendDescription = snapshot.backendDescription
		threadTokenUsage = snapshot.threadTokenUsage
		threadStatus = snapshot.threadStatus
		threadSettings = snapshot.threadSettings
		usage = UsagePresentation(
			snapshot,
			ownerIdentity: ownerIdentity
		)
	}
}
