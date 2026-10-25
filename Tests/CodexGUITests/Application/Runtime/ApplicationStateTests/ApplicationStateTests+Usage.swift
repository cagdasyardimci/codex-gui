import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{

	private func usageSnapshot(
		usedPercent: Double,
		windowDurationMins: Int,
		resetsAt: TimeInterval
	) -> AccountRateLimitsSnapshot
	{
		AccountRateLimitsSnapshot(json: [
			"rateLimits": ["primary": [
				"usedPercent": usedPercent,
				"windowDurationMins": windowDurationMins,
				"resetsAt": resetsAt,
			]],
		])!
	}

	private func awaitUsageClock(
		_ clock: ControlledUsageClock,
		matching predicate: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		let previous = clock.onWaitersChanged
		defer
		{
			clock.onWaitersChanged = previous
		}
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			clock.onWaitersChanged =
			{
				previous?()
				check()
			}
			check()
		}
		for await _ in stream
		{
			break
		}
		return predicate()
	}

	private func awaitUsagePublication(
		_ state: WorkspaceTestFixture,
		matching predicate: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		let previous = state.onChange
		defer
		{
			state.onChange = previous
		}
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			state.onChange =
			{
				snapshot in
				previous?(snapshot)
				check()
			}
			check()
		}
		for await _ in stream
		{
			break
		}
		return predicate()
	}
}
