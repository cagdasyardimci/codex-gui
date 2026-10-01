import Foundation

/// Account and execution chrome do not need transcript or composer values.
struct WorkspaceStatusPresentation: Equatable
{
	let executionState: ExecutionState
	let accountDescription: String
	let backendDescription: String
	let usage: UsagePresentation
	let threadTokenUsage: ThreadTokenUsage?
	let threadStatus: ThreadStatus?
	let threadSettings: ThreadSettings?
	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		executionState = snapshot.activeExecutionState ?? snapshot.executionState
		accountDescription = snapshot.accountDescription
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
