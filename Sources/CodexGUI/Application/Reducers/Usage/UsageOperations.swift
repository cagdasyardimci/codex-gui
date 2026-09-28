import Foundation

struct UsageReadOperation: Equatable
{
	let context: OperationContext
	let attempt: Int
}

struct UsageDeadlineOperation: Equatable
{
	let read: UsageReadOperation
	let fetchedAt: Date
	let deadline: Date
}

/// Clock access and suspension belong to the runtime, never to reducer values.
@MainActor
struct UsageRuntime
{
	var freshnessDuration: TimeInterval = 900
	var now: () -> Date = Date.init
	var waitUntil: (Date) async throws -> Void =
	{
		deadline in
		let delay = max(
			0,
			deadline.timeIntervalSinceNow
		)
		try await Task.sleep(for: .seconds(delay))
	}
}
