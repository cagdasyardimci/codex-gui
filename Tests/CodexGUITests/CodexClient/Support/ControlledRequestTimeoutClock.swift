import Foundation

/// Request deadlines advance only when the scenario releases them, independently of actor load.
actor ControlledRequestTimeoutClock
{
	private(set) var sleepCount = 0
	private var sleepers: [UUID: CheckedContinuation<Void, Error>] = [:]
	private var observers: [UUID: (count: Int, continuation: CheckedContinuation<Void, Error>)] =
		[:]

	var observerCount: Int
	{
		observers.count
	}

	func sleep(for duration: Duration) async throws
	{
		try Task.checkCancellation()
		let id = UUID()
		try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				(continuation: CheckedContinuation<Void, Error>) in
				guard !Task.isCancelled
				else
				{
					continuation.resume(throwing: CancellationError())
					return
				}
				sleepers[id] = continuation
				sleepCount += 1
				let ready = observers.filter
				{
					$0.value.count <= sleepCount
				}
				for (observerID, observer) in ready
				{
					observers.removeValue(forKey: observerID)
					observer.continuation.resume()
				}
			}
		}
		onCancel:
		{
			Task
			{
				await self.cancel(id)
			}
		}
		try Task.checkCancellation()
	}

	func waitForSleepCount(_ count: Int) async throws
	{
		try Task.checkCancellation()
		guard sleepCount < count
		else
		{
			return
		}
		let id = UUID()
		try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				(continuation: CheckedContinuation<Void, Error>) in
				guard !Task.isCancelled
				else
				{
					continuation.resume(throwing: CancellationError())
					return
				}
				observers[id] = (count, continuation)
			}
		}
		onCancel:
		{
			Task
			{
				await self.cancelObserver(id)
			}
		}
		try Task.checkCancellation()
	}

	func expirePending()
	{
		let pending = Array(sleepers.values)
		sleepers.removeAll()
		for continuation in pending
		{
			continuation.resume()
		}
	}

	private func cancel(_ id: UUID)
	{
		sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
	}

	private func cancelObserver(_ id: UUID)
	{
		observers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
	}
}
