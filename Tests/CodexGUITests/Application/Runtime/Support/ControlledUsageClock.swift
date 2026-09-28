import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class ControlledUsageClock
{
	private var time = Date(timeIntervalSince1970: 100)
	private var waiters: [(Date, CheckedContinuation<Void, Error>)] = []
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
				if self.time >= deadline
				{
					return
				}
				try await withCheckedThrowingContinuation
				{
					self.waiters.append((deadline, $0))
				}
			}
		)
	}

	func advance(by interval: TimeInterval)
	{
		time = time.addingTimeInterval(interval)
		let ready = waiters.filter
		{
			$0.0 <= time
		}
		waiters.removeAll
		{
			$0.0 <= time
		}
		for (_, continuation) in ready
		{
			continuation.resume()
		}
	}
}
