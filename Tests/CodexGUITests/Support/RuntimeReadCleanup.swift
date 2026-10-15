import Foundation

/// Joins the reads a controlled scenario started, including reads retired before it exits.
@MainActor
private final class RuntimeReadTaskRegistry
{
	private var tasks: [Task<Void, Never>] = []

	func capture(_ task: Task<Void, Never>?)
	{
		if let task
		{
			tasks.append(task)
		}
	}

	func finish() async
	{
		for task in tasks
		{
			task.cancel()
			await task.value
		}
	}
}

@MainActor
func withRuntimeReadCleanup(
	currentTask: @escaping @MainActor () -> Task<Void, Never>?,
	observeStarts: (@escaping @MainActor @Sendable () -> Void) async -> Void,
	stop: () -> Void,
	releasePending: () async -> Void,
	operation: () async throws -> Void
) async throws
{
	let reads = RuntimeReadTaskRegistry()
	await observeStarts
	{
		reads.capture(currentTask())
	}
	func cleanup() async
	{
		// A queued read might not have reached its service checkpoint yet.
		reads.capture(currentTask())
		stop()
		await releasePending()
		await reads.finish()
	}
	do
	{
		try await operation()
		await cleanup()
	}
	catch
	{
		await cleanup()
		throw error
	}
}
