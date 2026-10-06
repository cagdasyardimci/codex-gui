import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct WorkspaceLifecycleRuntimeTests
{

	@Test("Quit freeze rejects new draft writes while accepted persistence reduces and drains")
	func freezePreservesAcceptedWrite() async throws
	{
		let started = LifecycleRuntimeGate()
		let release = LifecycleRuntimeGate()
		var written: [String] = []
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				started.signal()
				await release.wait()
				written.append(write.draft.text)
			})
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/alpha"
		)
		let store = WorkspaceStateStore(
			model: WorkspaceModel(identity: identity),
			service: AppServer(),
			persistence: scheduler,
			reducers: [ComposerReducer.reducer, WorkspaceLifecycleReducer.reducer]
		)
		let context = store.operationContext()
		store.dispatch(.composer(.draftEdited(
			context,
			conversation: .newChat,
			text: "accepted",
			revision: 1
		)))
		let handle = try #require(store.operation(for: context))
		await started.wait()
		let quit = WorkspaceQuitRequest(requestID: UUID())
		#expect(store.freezeInputsForQuit(quit))
		store.dispatch(.composer(.draftEdited(
			store.operationContext(),
			conversation: .newChat,
			text: "rejected",
			revision: 2
		)))
		#expect(store.model.composer.drafts[.newChat]?.text == "accepted")
		#expect(handle.completion == nil)
		let barrier = Task
		{
			try await store.awaitAcceptedPersistence()
			try await store.drainPersistence()
		}
		release.signal()
		try await barrier.value
		#expect(written == ["accepted"])
		#expect(handle.completion == .finished)
		#expect(store.model.composer.pendingDraftWrites.isEmpty)
		store.thawInputsAfterQuit(WorkspaceQuitRequest(requestID: UUID()))
		#expect(store.model.lifecycle.quitReservation?.requestID == quit.requestID)
		store.thawInputsAfterQuit(quit)
		#expect(store.model.lifecycle.quitReservation == nil)
		store.shutdown()
	}

	@Test("Exact cleanup lease survives generation change and rejects a replaced lease")
	func cleanupLeaseIdentity() throws
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/task"
		)
		let managed = TaskWorkspace(
			id: UUID(),
			taskID: "task",
			threadID: nil,
			sourceProjectPath: "/source",
			repositoryGitDirectory: "/source/.git",
			branch: "codex/task",
			checkoutPath: "/task",
			baseCommit: "commit",
			sourceWasDirty: false,
			createdAt: .distantPast,
			phase: .active
		)
		var model = WorkspaceModel(identity: identity)
		model.lifecycle.owner = .managed(
			workspaceID: managed.id,
			sessionID: identity.sessionID
		)
		model.lifecycle.managedWorkspace = managed
		let owner = WorkspaceLifecycleReducer.reference(model)
		let first = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: owner,
			expected: managed
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReserved(first))
		)
		#expect(model.lifecycle.cleanupReservation == first)
		model.connection.generation += 1
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReleased(first))
		)
		#expect(model.lifecycle.cleanupReservation == nil)
		let second = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: owner,
			expected: managed
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReserved(second))
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReleased(first))
		)
		#expect(model.lifecycle.cleanupReservation == second)
		#expect(!WorkspaceLifecycleReducer.accepts(
			.connection(.projectOpened(
				WorkspaceIdentity(
					sessionID: identity.sessionID,
					canonicalCheckoutPath: "/other"
				),
				selectedThreadID: nil
			)),
			model: model
		))
	}

	@Test("Ownership conflict releases its exact lease and permits local drafts")
	func cleanupOwnershipConflict() throws
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/task"
		)
		let managed = TaskWorkspace(
			id: UUID(),
			taskID: "task",
			threadID: "original",
			sourceProjectPath: "/source",
			repositoryGitDirectory: "/source/.git",
			branch: "codex/task",
			checkoutPath: "/task",
			baseCommit: "commit",
			sourceWasDirty: false,
			createdAt: .distantPast,
			phase: .active
		)
		var model = WorkspaceModel(identity: identity)
		model.lifecycle.owner = .managed(
			workspaceID: managed.id,
			sessionID: identity.sessionID
		)
		model.lifecycle.managedWorkspace = managed
		let owner = WorkspaceLifecycleReducer.reference(model)
		let old = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: owner,
			expected: managed
		)
		let current = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: owner,
			expected: managed
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReserved(old))
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReleased(old))
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReserved(current))
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.managedRecordRecoveryConflicted(
				owner,
				expected: managed,
				cleanup: old,
				message: "obsolete conflict"
			))
		)
		#expect(model.lifecycle.cleanupReservation == current)
		#expect(model.lifecycle.managedOwnershipConflict == nil)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.managedRecordRecoveryConflicted(
				owner,
				expected: managed,
				cleanup: current,
				message: "binding changed"
			))
		)
		#expect(model.lifecycle.cleanupReservation == nil)
		#expect(model.lifecycle.managedWorkspace == managed)
		#expect(WorkspaceLifecycleReducer.blocksCleanup(model))
		let context = OperationContext(
			workspace: identity,
			generation: 0,
			requestID: UUID()
		)
		let edit = WorkspaceAction.composer(.draftEdited(
			context,
			conversation: .newChat,
			text: "local edit",
			revision: 1
		))
		#expect(WorkspaceLifecycleReducer.accepts(
			edit,
			model: model
		))
		_ = ComposerReducer.reduce(
			&model,
			edit
		)
		#expect(model.composer.drafts[.newChat]?.text == "local edit")
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "local edit"),
			inputs: [.text("local edit")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let remoteActions: [WorkspaceAction] = [
			.connection(.connectRequested(context)),
			.execution(.submissionRequested(submission)),
			.execution(.steeringRequested(SteeringOperation(
				context: context,
				submission: submission
			))),
			.conversations(.managementRequested(.archive(context))),
			.workspaceLifecycle(.cleanupReserved(current))
		]
		for action in remoteActions
		{
			#expect(!WorkspaceLifecycleReducer.accepts(
				action,
				model: model
			))
		}
		var foreign = managed
		foreign.threadID = "different"
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.managedRecordRecovered(
				owner,
				expected: managed,
				recovered: foreign
			))
		)
		#expect(model.lifecycle.managedWorkspace == managed)
		#expect(model.lifecycle.managedOwnershipConflict == "binding changed")

		// Durable removing phase also denies remote actions after the cleanup lease thaws.
		var removing = managed
		removing.phase = .removing
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.managedRecordRecovered(
				owner,
				expected: managed,
				recovered: removing
			))
		)
		#expect(model.lifecycle.managedOwnershipConflict == nil)
		#expect(model.lifecycle.managedWorkspace?.phase == .removing)
		#expect(WorkspaceLifecycleReducer.accepts(
			edit,
			model: model
		))
		for action in remoteActions.dropLast()
		{
			#expect(!WorkspaceLifecycleReducer.accepts(
				action,
				model: model
			))
		}
		let retry = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: owner,
			expected: removing
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.cleanupReserved(retry))
		)
		#expect(model.lifecycle.cleanupReservation == retry)
		#expect(!WorkspaceLifecycleReducer.accepts(
			edit,
			model: model
		))
	}

	@Test("A completed context save failure remains a barrier until a later successful revision")
	func completedContextFailure() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/alpha"
		))
		let context = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		let failed = ContextSaveOperation(
			context: context,
			revision: 1,
			value: ProjectContext()
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.contextNavigation(.contextPersistenceFinished(
				failed,
				.failed(OperationFailure(
					message: "disk failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(WorkspaceLifecycleComposition.persistenceFailure(model) == "disk failure")
		let retry = ContextSaveOperation(
			context: context,
			revision: 2,
			value: ProjectContext()
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.contextNavigation(.contextPersistenceFinished(
				retry,
				.succeeded(())
			))
		)
		#expect(WorkspaceLifecycleComposition.persistenceFailure(model) == nil)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.contextNavigation(.contextPersistenceFinished(
				failed,
				.failed(OperationFailure(
					message: "late failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(WorkspaceLifecycleComposition.persistenceFailure(model) == nil)
	}

}

@MainActor
private final class LifecycleRuntimeGate
{
	private var signaled = false
	private var waiters: [CheckedContinuation<Void, Never>] = []
	func signal()
	{
		signaled = true
		let pending = waiters
		waiters.removeAll()
		for waiter in pending
		{
			waiter.resume()
		}
	}
	func wait() async
	{
		if signaled
		{
			return
		}
		await withCheckedContinuation
		{
			waiters.append($0)
		}
	}
}
