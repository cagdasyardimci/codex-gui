import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct ProjectContextPersistenceRuntimeTests
{
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
