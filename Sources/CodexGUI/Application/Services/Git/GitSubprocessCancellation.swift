import Foundation

/// Carries caller cancellation into detached, synchronous Git reads.
final class GitSubprocessCancellation: @unchecked Sendable
{
	@TaskLocal static var current: GitSubprocessCancellation?

	private let lock = NSLock()
	private var activeProcess: Process?
	private var isCancelled = false

	static func detached<Value: Sendable>(
		_ operation: @escaping @Sendable () -> Value
	) async -> Value
	{
		let work = Task.detached
		{
			let control = GitSubprocessCancellation()
			return await $current.withValue(control)
			{
				await withTaskCancellationHandler
				{
					operation()
				} onCancel:
				{
					control.cancel()
				}
			}
		}
		return await withTaskCancellationHandler
		{
			await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	func launch(_ process: Process) throws
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		guard !isCancelled
		else
		{
			throw CancellationError()
		}
		try process.run()
		activeProcess = process
	}

	func finish(_ process: Process)
	{
		lock.lock()
		if activeProcess === process
		{
			activeProcess = nil
		}
		lock.unlock()
	}

	private func cancel()
	{
		lock.lock()
		isCancelled = true
		if let activeProcess, activeProcess.isRunning
		{
			activeProcess.terminate()
		}
		lock.unlock()
	}
}
