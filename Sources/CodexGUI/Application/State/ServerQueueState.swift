import Foundation

struct ServerQueueState
{
	enum Authority: Equatable
	{
		case probing, server, local
	}
	var authority: Authority = .probing
	var entries: [ThreadQueuedSubmission] = []
	var attemptedEnqueueID: UUID?
	var pending: ServerQueueOperation?
	var revision = 0
	var needsRefresh = true
	var awaitingStartedTurn = false
	var lastFailure: OperationFailure?
}

struct ServerQueueOperation
{
	enum Command
	{
		case refresh
		case add(QueuedComposerMessage)
		case update(QueuedComposerMessage)
		case delete(UUID)
		case reorder([UUID])
		case resume(UUID?)
	}
	let context: OperationContext
	let conversation: ConversationKey
	let revision: Int
	let command: Command
	let entries: [ThreadQueuedSubmission]
	let messages: [QueuedComposerMessage]
	let projectContext: ProjectContext
	let draftRevision: Int
	var isMutation: Bool
	{
		if case .refresh = command
		{
			return false
		}
		return true
	}
}

struct ServerQueueResult
{
	var unsupported = false
	var resumed = false
	var consumedClientIDs: Set<String> = []
	var entries: [ThreadQueuedSubmission]?
	var turn: CodexTurn?
	var refreshFailure: OperationFailure?
}

struct ServerQueueExecutionFailure: Error
{
	let failure: OperationFailure
}
