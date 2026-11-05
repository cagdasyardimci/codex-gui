import Foundation

/// Bounds and serializes access to one retained offline renderer.
@MainActor
final class MarkdownWebRendererQueue
{
	private var occupied = false
	private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

	func acquire() async -> Bool
	{
		guard !Task.isCancelled
		else
		{
			return false
		}
		if !occupied
		{
			occupied = true
			return true
		}
		guard waiters.count < 8
		else
		{
			return false
		}
		let id = UUID()
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				if Task.isCancelled
				{
					continuation.resume(returning: false)
				}
				else
				{
					waiters.append((id, continuation))
				}
			}
		} onCancel:
		{
			Task
			{
				@MainActor in
				guard let index = waiters.firstIndex(where:
					{
						$0.0 == id
					})
				else
				{
					return
				}
				waiters.remove(at: index).1.resume(returning: false)
			}
		}
	}

	func release()
	{
		if waiters.isEmpty
		{
			occupied = false
		}
		else
		{
			waiters.removeFirst().1.resume(returning: true)
		}
	}
}
