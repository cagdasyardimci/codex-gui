import Foundation

/// Synchronous reservations order background IO across stores sharing one persistence directory.
@MainActor
final class ProjectContextPersistenceWorker
{
	private final class WeakWorker
	{
		weak var value: ProjectContextPersistenceWorker?

		init(_ value: ProjectContextPersistenceWorker)
		{
			self.value = value
		}
	}

	private struct PendingOperation
	{
		let projectPath: String
		let task: Task<Void, Error>
	}

	private static var workers: [String: WeakWorker] = [:]
	let accessLock = NSLock()
	private var tail: Task<Void, Never>?
	private var pending: [UUID: PendingOperation] = [:]
	private var failedWrites: [String: Error] = [:]

	static func shared(forCanonicalDirectory directory: URL) -> ProjectContextPersistenceWorker
	{
		let path = directory.path
		if let worker = workers[path]?.value
		{
			return worker
		}
		workers = workers.filter
		{
			$0.value.value != nil
		}
		let worker = ProjectContextPersistenceWorker()
		workers[path] = WeakWorker(worker)
		return worker
	}

	func enqueue<Value: Sendable>(
		projectPath: String,
		isWrite: Bool,
		operation: @escaping @Sendable () async throws -> Value
	) -> Task<Value, Error>
	{
		enqueue(
			canonicalProjectPath: canonicalPath(projectPath),
			isWrite: isWrite,
			operation: operation
		)
	}

	/// Captured checkout identities must remain independent of later filesystem changes.
	func enqueue<Value: Sendable>(
		canonicalProjectPath: String,
		isWrite: Bool,
		operation: @escaping @Sendable () async throws -> Value
	) -> Task<Value, Error>
	{
		let previous = tail
		let id = UUID()
		// Accepted IO remains ordered when a caller stops waiting for its result.
		let task = Task.detached(priority: .utility)
		{
			await previous?.value
			return try await operation()
		}

		let completion = Task
		{
			defer
			{
				self.pending.removeValue(forKey: id)
			}
			do
			{
				_ = try await task.value
				if isWrite
				{
					self.failedWrites.removeValue(forKey: canonicalProjectPath)
				}
			}
			catch
			{
				if isWrite
				{
					self.failedWrites[canonicalProjectPath] = error
				}
				throw error
			}
		}
		pending[id] = PendingOperation(
			projectPath: canonicalProjectPath,
			task: completion
		)
		tail = Task
		{
			_ = await completion.result
		}
		return task
	}

	func hasPendingOperations(projectPath: String? = nil) -> Bool
	{
		hasPendingOperations(canonicalProjectPath: projectPath.map(canonicalPath))
	}

	func hasPendingOperations(canonicalProjectPath path: String?) -> Bool
	{
		pending.values.contains
		{
			path == nil || $0.projectPath == path
		}
	}

	func hasPendingPersistence(projectPath: String? = nil) -> Bool
	{
		hasPendingPersistence(canonicalProjectPath: projectPath.map(canonicalPath))
	}

	func hasPendingPersistence(canonicalProjectPath path: String?) -> Bool
	{
		hasPendingOperations(canonicalProjectPath: path) || failedWrites.keys.contains
		{
			path == nil || $0 == path
		}
	}

	func drain(projectPath: String? = nil) async throws
	{
		try await drain(canonicalProjectPath: projectPath.map(canonicalPath))
	}

	/// Lifecycle barriers use the captured identity rather than the checkout's current symlinks.
	func drain(canonicalProjectPath path: String?) async throws
	{
		while true
		{
			let operations = pending.values.filter
			{
				path == nil || $0.projectPath == path
			}
			guard !operations.isEmpty
			else
			{
				break
			}
			for operation in operations
			{
				_ = await operation.task.result
			}
		}
		if let error = failedWrites.first(where:
			{
				path == nil || $0.key == path
			})?.value
		{
			throw error
		}
	}

	private func canonicalPath(_ path: String) -> String
	{
		URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
	}
}
