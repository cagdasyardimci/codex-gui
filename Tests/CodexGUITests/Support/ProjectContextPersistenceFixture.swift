import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct ProjectContextPersistenceFixture
{
	let directory: URL
	let project: URL
	let storageDirectory: URL
	let contexts: ProjectContextStore

	init(fileManager: FileManager = .default) throws
	{
		directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			.resolvingSymlinksInPath()
		project = directory.appendingPathComponent("project")
		storageDirectory = directory.appendingPathComponent("data")
		contexts = ProjectContextStore(
			directory: storageDirectory,
			fileManager: fileManager
		)
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
	}

	func identity() -> WorkspaceIdentity
	{
		WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project.path
		)
	}

	func context(_ title: String) -> ProjectContext
	{
		var context = ProjectContext()
		context.items = [ProjectContextItem(
			kind: .note,
			title: title,
			body: "Retain exactly \(title)"
		)]
		return context
	}

	func workspaceStore() -> WorkspaceStateStore
	{
		var model = WorkspaceModel(identity: identity())
		model.connection.isConnected = true
		model.execution.state = .ready
		return WorkspaceStateStore(
			model: model,
			service: MockCodexService(),
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			projectContextStore: contexts,
			reducers: [ContextNavigationReducer.reducer, WorkspaceLifecycleReducer.reducer]
		)
	}

	func runner(deliver: @escaping (
		WorkspaceAction,
		@escaping () -> Void
	) -> Void =
	{
		_, completed in completed()
	}) -> WorkspaceEffectRunner
	{
		WorkspaceEffectRunner(
			service: MockCodexService(),
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			projectContextStore: contexts,
			mapEvent:
			{
				_, _ in []
			},
			deliver: deliver
		)
	}

	func blockWorker() -> (started: ProjectContextRuntimeGate, release: ProjectContextRuntimeGate)
	{
		let started = ProjectContextRuntimeGate()
		let release = ProjectContextRuntimeGate()
		_ = contexts.persistenceWorker.enqueue(
			projectPath: project.path,
			isWrite: false
		)
		{
			await started.signal()
			await release.wait()
		}
		return (started, release)
	}

	func remove()
	{
		try? FileManager.default.removeItem(at: directory)
	}
}

actor ProjectContextRuntimeGate
{
	private var released = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func wait() async
	{
		guard !released
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters.append($0)
		}
	}

	func signal()
	{
		released = true
		let pending = waiters
		waiters.removeAll()
		for waiter in pending
		{
			waiter.resume()
		}
	}
}
