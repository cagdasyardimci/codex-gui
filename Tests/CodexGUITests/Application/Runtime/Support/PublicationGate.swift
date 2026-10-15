import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class PublicationGate
{
	private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
	var onWaitersChanged: (() -> Void)?
	var waiterCount: Int
	{
		continuations.count
	}
	var isWaiting: Bool
	{
		!continuations.isEmpty
	}

	func wait() async
	{
		let id = UUID()
		// Cancellation must release suspension even when a scenario never opens the gate.
		await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				guard !Task.isCancelled
				else
				{
					continuation.resume()
					return
				}
				continuations[id] = continuation
				onWaitersChanged?()
			}
		}
		onCancel:
		{
			Task
			{
				@MainActor in
				self.cancel(id)
			}
		}
	}

	func release()
	{
		let pending = Array(continuations.values)
		continuations.removeAll()
		if !pending.isEmpty
		{
			onWaitersChanged?()
		}
		for continuation in pending
		{
			continuation.resume()
		}
	}

	private func cancel(_ id: UUID)
	{
		// Remove only this wait before resuming.
		// Release and replacement waits can race cancellation.
		guard let continuation = continuations.removeValue(forKey: id)
		else
		{
			return
		}
		onWaitersChanged?()
		continuation.resume()
	}
}
