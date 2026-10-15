import Foundation

@testable import CodexGUI

/// Holds preparation in a background worker while a test changes the captured UI owner.
final class DraftImageImportTestGate: @unchecked Sendable
{
	private let condition = NSCondition()
	private var startedCount = 0
	private var released = false
	private var startWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

	var preparationCount: Int
	{
		condition.lock()
		defer
		{
			condition.unlock()
		}
		return startedCount
	}

	func prepare(_ source: DraftImageSource) throws -> Data
	{
		condition.lock()
		startedCount += 1
		let started = Array(startWaiters.values)
		startWaiters.removeAll()
		condition.unlock()
		for waiter in started
		{
			waiter.resume(returning: true)
		}
		condition.lock()
		// The scenario releases the held worker after changing its owner, not after a deadline.
		while !released
		{
			condition.wait()
		}
		condition.unlock()
		return try source.pngData()
	}

	func waitUntilStarted() async -> Bool
	{
		let id = UUID()
		// A blocking observer would consume the same worker pool needed to start preparation.
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				condition.lock()
				if startedCount > 0
				{
					condition.unlock()
					continuation.resume(returning: true)
				}
				else if released || Task.isCancelled
				{
					condition.unlock()
					continuation.resume(returning: false)
				}
				else
				{
					startWaiters[id] = continuation
					condition.unlock()
				}
			}
		}
		onCancel:
		{
			self.cancelStartWaiter(id)
		}
	}

	private func cancelStartWaiter(_ id: UUID)
	{
		condition.lock()
		let waiter = startWaiters.removeValue(forKey: id)
		condition.unlock()
		waiter?.resume(returning: false)
	}

	func release()
	{
		condition.lock()
		released = true
		let waiters = Array(startWaiters.values)
		startWaiters.removeAll()
		condition.broadcast()
		condition.unlock()
		for waiter in waiters
		{
			waiter.resume(returning: false)
		}
	}
}
