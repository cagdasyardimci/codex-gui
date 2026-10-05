import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
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
		let project = try makeProject()
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaults),
			publicationWait: publicationWait
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		state.inputs.updateDraft("Run request")
		let submission = try #require(state.inputs.send())
		_ = await submission.wait()
		try #require(await waitUntil
		{
			state.currentSnapshot.canSteer
		})
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

	func makeProject() throws -> URL
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

	func makeTurn(
		id: String,
		status: String,
		items: [[String: Any]] = []
	) -> CodexTurn
	{
		CodexTurn(json: ["id": id, "status": status, "items": items])!
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
