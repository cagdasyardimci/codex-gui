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
