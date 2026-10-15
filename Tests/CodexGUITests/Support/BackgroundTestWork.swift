import Foundation

/// Runs independent blocking fixture work without occupying MainActor or Swift's worker pool.
enum BackgroundTestWork
{
	private static let queue: OperationQueue =
	{
		let queue = OperationQueue()
		queue.name = "CodexGUI.TestFixtureWork"
		queue.qualityOfService = .utility
		// Bound subprocess and disk contention when many parallel tests prepare repositories.
		queue.maxConcurrentOperationCount = 4
		return queue
	}()

	static func perform<Value: Sendable>(
		_ operation: @escaping @Sendable () throws -> Value
	) async throws -> Value
	{
		try Task.checkCancellation()
		let timing = TestTiming.begin("fixture.io")
		defer
		{
			timing.end()
		}
		return try await withCheckedThrowingContinuation
		{
			continuation in
			queue.addOperation
			{
				timing.mark("execution.begin")
				let result = Result
				{
					try timing.withWorkerContext(operation)
				}
				// Finish the worker marker before the resumed task can end its enclosing span.
				timing.mark("execution.end")
				continuation.resume(with: result)
			}
		}
	}
}
