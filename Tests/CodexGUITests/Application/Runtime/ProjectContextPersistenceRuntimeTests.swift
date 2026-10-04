import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct ProjectContextPersistenceRuntimeTests
{
	@Test("Shared storage reservations preserve save/load order across facade instances")
	func sharedDirectoryOrdersSaveAndLoad() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		try FileManager.default.createDirectory(
			at: fixture.storageDirectory,
			withIntermediateDirectories: true
		)
		let storageAlias = fixture.directory.appendingPathComponent("data-alias")
		try FileManager.default.createSymbolicLink(
			at: storageAlias,
			withDestinationURL: fixture.storageDirectory
		)
		let second = ProjectContextStore(directory: storageAlias)
		#expect(fixture.contexts.persistenceWorker === second.persistenceWorker)
		#expect(fixture.contexts.fileURL(for: fixture.project) == second
			.fileURL(for: fixture.project))
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		let firstValue = fixture.context("First")
		let secondValue = fixture.context("Second")
		let firstSave = fixture.contexts.enqueueSave(
			firstValue,
			for: fixture.project
		)
		let firstRead = second.enqueueLoad(for: fixture.project)
		let secondSave = second.enqueueSave(
			secondValue,
			for: fixture.project
		)
		let secondRead = fixture.contexts.enqueueLoad(for: fixture.project)
		#expect(second.persistenceWorker.hasPendingOperations(projectPath: fixture.project.path))
		await blocker.release.signal()
		try await firstSave.value
		#expect(try await firstRead.value == firstValue)
		try await secondSave.value
		#expect(try await secondRead.value == secondValue)
		try await second.persistenceWorker.drain()
		#expect(!fixture.contexts.persistenceWorker.hasPendingOperations())
	}

	@Test("Queued context IO retains its accepted checkout after a symlink is retargeted")
	func queuedCheckoutAliasRetainsItsCapturedProject() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let otherProject = fixture.directory.appendingPathComponent("other-project")
		try FileManager.default.createDirectory(
			at: otherProject,
			withIntermediateDirectories: true
		)
		let alias = fixture.directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		defer
		{
			Task
			{
				await blocker.release.signal()
			}
		}
		let acceptedContext = fixture.context("Accepted owner")
		let save = fixture.contexts.enqueueSave(
			acceptedContext,
			for: alias
		)
		let load = fixture.contexts.enqueueLoad(for: alias)

		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: otherProject
		)
		#expect(!fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))
		await blocker.release.signal()
		try await save.value
		#expect(try await load.value == acceptedContext)
		try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
		#expect(try fixture.contexts.load(for: fixture.project) == acceptedContext)
		#expect(try fixture.contexts.load(for: otherProject) == ProjectContext())
	}

	@Test("Accepted IO and its drain retain a bucket when its physical checkout becomes a symlink")
	func queuedPhysicalCheckoutReplacementPreservesItsAcceptedBucketAndDrain() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let otherProject = fixture.directory.appendingPathComponent("other-project")
		try FileManager.default.createDirectory(
			at: otherProject,
			withIntermediateDirectories: true
		)
		let capturedPath = fixture.project.path
		let originalDocumentURL = fixture.contexts.fileURL(for: fixture.project)
		let replacementDocumentURL = fixture.contexts.fileURL(for: otherProject)
		let acceptedContext = fixture.context("Keep the accepted bucket")
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		defer
		{
			Task
			{
				await blocker.release.signal()
			}
		}
		let save = fixture.contexts.enqueueSave(
			acceptedContext,
			for: fixture.project
		)
		let load = fixture.contexts.enqueueLoad(for: fixture.project)

		try FileManager.default.moveItem(
			at: fixture.project,
			to: fixture.directory.appendingPathComponent("moved-project")
		)
		try FileManager.default.createSymbolicLink(
			at: fixture.project,
			withDestinationURL: otherProject
		)
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(canonicalProjectPath: capturedPath))
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))

		var didFinishDrain = false
		var drain: Task<Void, Error>?
		await withCheckedContinuation
		{
			(started: CheckedContinuation<Void, Never>) in
			drain = Task
			{
				started.resume()
				try await fixture.contexts.persistenceWorker.drain(
					canonicalProjectPath: capturedPath
				)
				didFinishDrain = true
			}
		}
		let acceptedDrain = try #require(drain)
		#expect(!didFinishDrain)

		await blocker.release.signal()
		try await acceptedDrain.value
		try await save.value
		#expect(try await load.value == acceptedContext)
		#expect(didFinishDrain)
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingOperations(canonicalProjectPath: capturedPath))
		let documentData = try Data(contentsOf: originalDocumentURL)
		let document = try #require(
			JSONSerialization.jsonObject(with: documentData) as? [String: Any]
		)
		#expect(document["projectPath"] as? String == capturedPath)
		#expect(!FileManager.default.fileExists(atPath: replacementDocumentURL.path))
		#expect(try fixture.contexts.load(for: fixture.project) == ProjectContext())
		#expect(try fixture.contexts.load(for: otherProject) == ProjectContext())
	}

	@Test("An alias and canonical checkout share the same failed-write and recovery barrier")
	func checkoutAliasesShareFailureAndRecoveryBarriers() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let alias = fixture.directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		try fixture.contexts.save(
			ProjectContext(),
			for: fixture.project
		)
		let documentURL = fixture.contexts.fileURL(for: fixture.project)
		let originalData = try Data(contentsOf: documentURL)
		try Data("{broken".utf8).write(to: documentURL)
		let acceptedContext = fixture.context("Retry through the canonical checkout")
		_ = await fixture.contexts.enqueueSave(
			acceptedContext,
			for: alias
		).result

		do
		{
			try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
			Issue.record("The canonical checkout lost the alias's failed-write barrier.")
		}
		catch is ProjectContextStoreError
		{
		}
		#expect(fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))

		try originalData.write(to: documentURL)
		try await fixture.contexts.enqueueSave(
			acceptedContext,
			for: fixture.project
		).value
		try await fixture.contexts.persistenceWorker.drain(projectPath: alias.path)
		#expect(!fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))
		#expect(try fixture.contexts.load(for: fixture.project) == acceptedContext)
	}

	@Test("Pending loads block submission; a newer edit rejects the late load result")
	func pendingLoadProtectsSubmissionAndLaterEdits() async throws
	{
		let manager = ContextIORecordingFileManager()
		let fixture = try ProjectContextPersistenceFixture(fileManager: manager)
		defer
		{
			fixture.remove()
		}
		try fixture.contexts.save(
			fixture.context("Stored"),
			for: fixture.project
		)
		manager.resetAccesses()
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		let store = fixture.workspaceStore()
		defer
		{
			store.shutdown()
		}
		#expect(WorkspaceEligibility(model: store.model).canSend)
		let load = ContextLoadOperation(
			context: store.operationContext(),
			revision: 0
		)
		store.dispatch(.contextNavigation(.contextLoadRequested(load)))
		let loadHandle = try #require(store.operation(for: load.context))
		#expect(loadHandle.completion == nil)
		#expect(WorkspaceEligibility(model: store.model).preferenceWarning
			== "Project context is loading.")
		#expect(!WorkspaceEligibility(model: store.model).canSend)
		let edit = ContextSaveOperation(
			context: store.operationContext(),
			revision: 1,
			value: fixture.context("New edit")
		)
		store.dispatch(.contextNavigation(.contextEdited(edit)))
		let saveHandle = try #require(store.operation(for: edit.context))
		#expect(store.model.contextNavigation.projectContext == edit.value)
		await blocker.release.signal()
		#expect(await loadHandle.wait() == .finished)
		#expect(store.model.contextNavigation.projectContext == edit.value)
		#expect(await saveHandle.wait() == .finished)
		try await store.drainPersistence()
		#expect(manager.accessesOccurredOffMain)
		#expect(store.model.contextNavigation.pendingContextLoad == nil)
		#expect(WorkspaceEligibility(model: store.model).canSend)
		#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
	}

	@Test("Quit waits for accepted context writes while rejecting later edits")
	func quitBarrierPreservesAcceptedWrite() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		let store = fixture.workspaceStore()
		defer
		{
			store.shutdown()
		}
		let edit = ContextSaveOperation(
			context: store.operationContext(),
			revision: 1,
			value: fixture.context("Accepted")
		)
		store.dispatch(.contextNavigation(.contextEdited(edit)))
		let handle = try #require(store.operation(for: edit.context))
		let quit = WorkspaceQuitRequest(requestID: UUID())
		#expect(store.freezeInputsForQuit(quit))
		store.dispatch(.contextNavigation(.contextEdited(ContextSaveOperation(
			context: store.operationContext(),
			revision: 2,
			value: fixture.context("Rejected")
		))))
		#expect(store.model.contextNavigation.projectContext == edit.value)
		var drained = false
		let barrier = Task
		{
			try await store.awaitAcceptedPersistence()
			try await store.drainPersistence()
			drained = true
		}
		await Task.yield()
		#expect(!drained)
		#expect(handle.completion == nil)
		await blocker.release.signal()
		try await barrier.value
		#expect(handle.completion == .finished)
		#expect(store.model.contextNavigation.pendingContextSave == nil)
		#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
		#expect(!fixture.contexts.persistenceWorker.hasPendingOperations())
	}

	@Test("A shutdown before effect start retains reserved writes for the drain barrier")
	func shutdownRetainsReservedPersistence() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		let identity = fixture.identity()
		let runner = fixture.runner()
		let edit = ContextSaveOperation(
			context: OperationContext(
				workspace: identity,
				generation: 0,
				requestID: UUID()
			),
			revision: 1,
			value: fixture.context("Reserved")
		)
		runner.reserve(
			[.saveProjectContext(edit)],
			workspace: identity
		)
		#expect(runner.pendingAcceptedPersistenceCount == 1)
		#expect(runner.hasPendingPersistence(projectPath: fixture.project.path))
		runner.shutdown()
		#expect(runner.hasPendingPersistence(projectPath: fixture.project.path))
		var drained = false
		let barrier = Task
		{
			try await runner.awaitAcceptedPersistence()
			try await runner.drainPersistence(projectPath: fixture.project.path)
			drained = true
		}
		await Task.yield()
		#expect(!drained)
		await blocker.release.signal()
		try await barrier.value
		#expect(!runner.hasPendingPersistence(projectPath: fixture.project.path))
		#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
	}

	@Test("Shutdown waits for a reserved context write after its checkout alias is retargeted")
	func shutdownBarrierRetainsTheReservedCheckoutAfterAliasRetargeting() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let otherProject = fixture.directory.appendingPathComponent("other-project")
		try FileManager.default.createDirectory(
			at: otherProject,
			withIntermediateDirectories: true
		)
		let alias = fixture.directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		defer
		{
			Task
			{
				await blocker.release.signal()
			}
		}
		let runner = fixture.runner()
		defer
		{
			runner.shutdown()
		}
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: alias.path
		)
		let edit = ContextSaveOperation(
			context: OperationContext(
				workspace: identity,
				generation: 0,
				requestID: UUID()
			),
			revision: 1,
			value: fixture.context("Accepted before shutdown")
		)
		runner.reserve(
			[.saveProjectContext(edit)],
			workspace: identity
		)
		#expect(runner.pendingAcceptedPersistenceCount == 1)

		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: otherProject
		)
		runner.shutdown()
		#expect(runner.pendingAcceptedPersistenceCount == 0)
		#expect(runner.hasPendingPersistence(projectPath: fixture.project.path))

		var didFinishBarrier = false
		var barrier: Task<Void, Error>?
		await withCheckedContinuation
		{
			(started: CheckedContinuation<Void, Never>) in
			barrier = Task
			{
				started.resume()
				try await runner.awaitAcceptedPersistence()
				didFinishBarrier = true
			}
		}
		let acceptedBarrier = try #require(barrier)
		#expect(!didFinishBarrier)

		await blocker.release.signal()
		try await acceptedBarrier.value
		try await runner.drainPersistence(projectPath: fixture.project.path)
		#expect(didFinishBarrier)
		#expect(!runner.hasPendingPersistence(projectPath: fixture.project.path))
		#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
		#expect(try fixture.contexts.load(for: otherProject) == ProjectContext())
	}

	@Test("Cancellation retires result delivery while the captured write remains ordered")
	func cancellationPreservesCapturedWriteAndOwner() async throws
	{
		let fixture = try ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		var actions: [WorkspaceAction] = []
		let runner = fixture.runner(deliver:
			{
				action, completed in
				actions.append(action)
				completed()
			})
		defer
		{
			runner.shutdown()
		}
		let identity = fixture.identity()
		let edit = ContextSaveOperation(
			context: OperationContext(
				workspace: identity,
				generation: 0,
				requestID: UUID()
			),
			revision: 1,
			value: fixture.context("Original owner")
		)
		runner.accept(
			[.saveProjectContext(edit)],
			workspace: identity
		)
		let handle = try #require(runner.operation(for: edit.context))
		runner.cancel(edit.context)
		#expect(handle.completion == .cancelled)
		#expect(actions.count == 1)
		await blocker.release.signal()
		try await runner.drainPersistence()
		await Task.yield()
		#expect(actions.count == 1)
		#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
		#expect(try fixture.contexts.load(for: fixture.directory
				.appendingPathComponent("another-owner")) == ProjectContext())
	}

	@Test("Queued writes revalidate external bytes and retain scoped failure barriers until retry")
	func externalProtectedDocumentsRemainUnchanged() async throws
	{
		for field in ["corrupt", "version", "projectPath"]
		{
			let fixture = try ProjectContextPersistenceFixture()
			defer
			{
				fixture.remove()
			}
			try fixture.contexts.save(
				ProjectContext(),
				for: fixture.project
			)
			let file = fixture.contexts.fileURL(for: fixture.project)
			let original = try Data(contentsOf: file)
			var document = try #require(
				JSONSerialization.jsonObject(with: original) as? [String: Any]
			)
			document[field] = field == "version" ? (999 as Any) : ("/another/project" as Any)
			let external = field == "corrupt" ? Data("{broken".utf8)
				: try JSONSerialization.data(withJSONObject: document)
			let blocker = fixture.blockWorker()
			await blocker.started.wait()
			let edit = fixture.context("Keep this edit")
			let write = fixture.contexts.enqueueSave(
				edit,
				for: fixture.project
			)
			try external.write(to: file)
			await blocker.release.signal()
			let outcome = await write.result
			if case .success = outcome
			{
				Issue.record("The queued write replaced protected external bytes.")
			}
			#expect(try Data(contentsOf: file) == external)
			var failedBarrier = false
			do
			{
				try await fixture.contexts.persistenceWorker
					.drain(projectPath: fixture.project.path)
			}
			catch
			{
				failedBarrier = true
			}
			#expect(failedBarrier)
			#expect(fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: fixture.project.path))
			#expect(!fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: "/unrelated"))
			try await fixture.contexts.persistenceWorker.drain(projectPath: "/unrelated")
			try original.write(to: file)
			try await fixture.contexts.enqueueSave(
				edit,
				for: fixture.project
			).value
			try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
			#expect(!fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: fixture.project.path))
			#expect(try fixture.contexts.load(for: fixture.project) == edit)
		}
	}
}

@MainActor
private struct ProjectContextPersistenceFixture
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

private actor ProjectContextRuntimeGate
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

private final class ContextIORecordingFileManager: FileManager, @unchecked Sendable
{
	private let accessLock = NSLock()
	private var accessMainThread: [Bool] = []

	var accessesOccurredOffMain: Bool
	{
		accessLock.withLock
		{
			!accessMainThread.isEmpty && accessMainThread.allSatisfy
			{
				!$0
			}
		}
	}

	func resetAccesses()
	{
		accessLock.withLock
		{
			accessMainThread.removeAll()
		}
	}

	override func fileExists(atPath path: String) -> Bool
	{
		accessLock.withLock
		{
			accessMainThread.append(Thread.isMainThread)
		}
		return super.fileExists(atPath: path)
	}
}
