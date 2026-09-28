import Foundation

enum WorkspaceOperationCompletion: Equatable
{
	case finished
	case failed(OperationFailure)
	case cancelled
}

/// Finite operation completion includes synchronous reduction of the returned result.
/// Backend subscriptions are deliberately excluded from these handles.
@MainActor
final class WorkspaceOperationHandle
{
	let context: OperationContext
	private(set) var completion: WorkspaceOperationCompletion?
	private var pendingCount = 0
	private var result: WorkspaceOperationCompletion = .finished
	private var waiters: [CheckedContinuation<WorkspaceOperationCompletion, Never>] = []

	init(context: OperationContext)
	{
		self.context = context
	}

	func wait() async -> WorkspaceOperationCompletion
	{
		if let completion
		{
			return completion
		}
		return await withCheckedContinuation
		{
			waiters.append($0)
		}
	}

	func cancelRemainingEffects()
	{
		guard completion == nil
		else
		{
			return
		}
		pendingCount = 1
		finishedEffect(.cancelled)
	}

	func acceptedEffect()
	{
		pendingCount += 1
	}

	func finishedEffect(_ outcome: WorkspaceOperationCompletion)
	{
		guard completion == nil, pendingCount > 0
		else
		{
			return
		}
		if outcome != .finished
		{
			result = outcome
		}
		pendingCount -= 1
		guard pendingCount == 0
		else
		{
			return
		}
		completion = result
		let continuations = waiters
		waiters.removeAll()
		for waiter in continuations
		{
			waiter.resume(returning: result)
		}
	}
}
