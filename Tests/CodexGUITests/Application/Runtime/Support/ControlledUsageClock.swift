import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class ControlledUsageClock
{
	private var time = Date(timeIntervalSince1970: 100)
	private var waiters: [
		(id: UUID, deadline: Date, continuation: CheckedContinuation<Void, Error>)
	] = []
	var onWaitersChanged: (() -> Void)?
	var waiterCount: Int
	{
		waiters.count
	}

	var runtime: UsageRuntime
	{
		UsageRuntime(
			freshnessDuration: 50,
			now:
			{
				self.time
			},
			waitUntil:
			{
				deadline in
				try await self.wait(until: deadline)
			}
		)
	}

	func advance(by interval: TimeInterval)
	{
		time = time.addingTimeInterval(interval)
		let readyWaiters = waiters.filter
		{
			$0.deadline <= time
		}

		waiters.removeAll
		{
			$0.deadline <= time
		}

		if !readyWaiters.isEmpty
		{
			onWaitersChanged?()
		}
		for (_, _, continuation) in readyWaiters
		{
			continuation.resume()
		}
	}

	private func wait(until deadline: Date) async throws
	{
		try Task.checkCancellation()
		guard time < deadline
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
				// The handler may run before registration; check again while owning the actor.
				guard !Task.isCancelled
				else
				{
					continuation.resume(throwing: CancellationError())
					return
				}
				waiters.append((id, deadline, continuation))
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
		// Advancing the clock can win removal while the resumed task is already canceled.
		try Task.checkCancellation()
	}

	private func cancel(_ id: UUID)
	{
		guard let index = waiters.firstIndex(where:
			{
				$0.id == id
			})
		else
		{
			return
		}
		let waiter = waiters.remove(at: index)
		onWaitersChanged?()
		waiter.continuation.resume(throwing: CancellationError())
	}
}
