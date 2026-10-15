import Foundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ControlledRequestTimeoutClockTests
{
	@Test(arguments: [false, true])
	func canceledReadinessObservationLeavesOtherObserversUsable(
		afterRegistration: Bool
	) async throws
	{
		let clock = ControlledRequestTimeoutClock()
		let completions = AsyncStream<String>.makeStream()
		defer
		{
			completions.continuation.finish()
		}
		let active = Task
		{
			do
			{
				try await clock.waitForSleepCount(1)
				completions.continuation.yield("active")
			}
			catch
			{
				completions.continuation.yield("active failed: \(error)")
			}
		}
		defer
		{
			active.cancel()
		}
		try await waitForObservers(
			1,
			in: clock
		)
		let canceled = Task
		{
			do
			{
				try await clock.waitForSleepCount(1)
				completions.continuation.yield("canceled observation returned successfully")
			}
			catch is CancellationError
			{
				completions.continuation.yield("canceled")
			}
			catch
			{
				completions.continuation.yield("unexpected cancellation error: \(error)")
			}
		}
		defer
		{
			canceled.cancel()
		}
		if afterRegistration
		{
			try await waitForObservers(
				2,
				in: clock
			)
		}
		// Before the first suspension, this MainActor task cannot register its observation.
		canceled.cancel()
		try await waitForObservers(
			1,
			in: clock
		)
		var completed = completions.stream.makeAsyncIterator()
		try #require(await completed.next() == "canceled")
		#expect(await clock.observerCount == 1)
		let sleep = Task
		{
			do
			{
				try await clock.sleep(for: .seconds(3))
				completions.continuation.yield("expired")
			}
			catch
			{
				completions.continuation.yield("sleep failed: \(error)")
			}
		}
		defer
		{
			sleep.cancel()
		}
		try #require(await completed.next() == "active")
		#expect(await clock.observerCount == 0)
		await clock.expirePending()
		try #require(await completed.next() == "expired")
	}

	private func waitForObservers(
		_ count: Int,
		in clock: ControlledRequestTimeoutClock
	) async throws
	{
		let deadline = ContinuousClock.now.advanced(by: .seconds(3))
		while await clock.observerCount != count, ContinuousClock.now < deadline
		{
			try await Task.sleep(for: .milliseconds(1))
		}
		try #require(await clock.observerCount == count)
	}
}
