import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	/// Opening a checkout starts context IO independently of connection and thread selection.
	func awaitProjectContextLoad(_ state: WorkspaceTestFixture) async throws
	{
		// Reconnection can replace a load, so await current readiness rather than a retired handle.
		await awaitWorkspaceSnapshot(state.store)
		{
			_ in state.store.model.contextNavigation.pendingContextLoad == nil
		}
		try #require(state.store.model.contextNavigation.pendingContextLoad == nil)
	}

	/// Usability is published after independent context and conversation initialization.
	func awaitSubmissionReadiness(_ state: WorkspaceTestFixture) async
	{
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSend
		}
	}

	func contextStore(
		model: WorkspaceModel,
		service: MockCodexService
	) -> WorkspaceStateStore
	{
		WorkspaceStateStore(
			model: model,
			service: service,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [WorkspaceFeatureComposition.reducer],
			reduceDomainEvent: WorkspaceDomainComposition.reduceDomainEvent
		)
	}

	func contextModel() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/private/tmp"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread("thread-1")
		return model
	}

	func makeRunningState(
		defaults: UserDefaults,
		publicationWait: @escaping @MainActor () async -> Void =
		{
			try? await Task.sleep(for: .milliseconds(50))
		}
	) async throws
		-> (WorkspaceTestFixture, MockCodexService, URL)
	{
		let project = try await makeProject()
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaults),
			publicationWait: publicationWait
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try await awaitProjectContextLoad(state)
		state.inputs.selectThread(service.thread.id)
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSend
		}
		try #require(state.currentSnapshot.canSend)
		state.inputs.updateDraft("Run request")
		let submission = try #require(state.inputs.send())
		_ = await submission.wait()
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSteer
		}
		try #require(state.currentSnapshot.canSteer)
		return (state, service, project)
	}

	func makeInteraction(
		id: String,
		kind: InteractionKind
	) -> PendingInteraction
	{
		PendingInteraction(
			id: id,
			threadId: "thread-1",
			turnId: "turn-1",
			itemId: id,
			approvalId: nil,
			kind: kind,
			reason: nil,
			command: nil,
			cwd: nil,
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: nil,
			additionalPermissions: nil,
			availableDecisions: nil
		)
	}

	nonisolated func makeProject() async throws -> URL
	{
		// Checkout preparation performs independent file IO; it does not need the store's actor.
		try await BackgroundTestWork.perform
		{
			let project = FileManager.default.temporaryDirectory.appendingPathComponent(
				"CodexGUIStateTests-\(UUID().uuidString)",
				isDirectory: true
			)
			try FileManager.default.createDirectory(
				at: project.appendingPathComponent(
					".git",
					isDirectory: true
				),
				withIntermediateDirectories: true
			)
			return project
		}
	}

	func makeTurn(
		id: String,
		status: String,
		items: [[String: Any]] = []
	) -> CodexTurn
	{
		CodexTurn(json: ["id": id, "status": status, "items": items])!
	}

	/// Wait only on the fixture that can satisfy this condition; no scheduling budget is involved.
	func awaitApplicationStateCondition(
		_ state: WorkspaceTestFixture,
		service: MockCodexService? = nil,
		matching condition: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		guard let service
		else
		{
			await awaitWorkspaceSnapshot(state.store)
			{
				_ in condition()
			}
			return condition()
		}
		var storeObservation: UUID?
		var serviceObservation: UUID?
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard condition()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			storeObservation = state.store.observe
			{
				_ in check()
			}
			// A mock continuation can be installed after the store's last publication.
			serviceObservation = service.observeReadiness(check)
		}
		for await _ in stream
		{
			break
		}
		if let storeObservation
		{
			state.store.removeObserver(storeObservation)
		}
		if let serviceObservation
		{
			service.removeReadinessObserver(serviceObservation)
		}
		return condition()
	}

	/// Each completed effect can accept follow-up work before returning to its caller.
	func awaitApplicationStateOperations(_ state: WorkspaceTestFixture) async -> Bool
	{
		while state.pendingBackendOperationCount > 0
		{
			let tasks = state.store.executionTasks()
			guard !tasks.isEmpty, !Task.isCancelled
			else
			{
				return false
			}
			for task in tasks
			{
				await task.value
			}
		}
		return state.pendingBackendOperationCount == 0
	}

	func awaitPublicationGateCondition(
		_ gate: PublicationGate,
		matching condition: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		let previous = gate.onWaitersChanged
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard condition()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			gate.onWaitersChanged =
			{
				previous?()
				check()
			}
			check()
		}
		for await _ in stream
		{
			break
		}
		// AsyncStream iteration terminates on cancellation as well as successful readiness.
		gate.onWaitersChanged = previous
		return condition()
	}
	func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 200
		{
			if condition()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return condition()
	}

}
