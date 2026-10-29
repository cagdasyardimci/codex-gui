import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class ConcurrentChatFixture
{
	let project: URL
	let defaults: IsolatedUserDefaultsFixture
	let service: ConcurrentChatService
	let fixture: WorkspaceTestFixture

	init() throws
	{
		project = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ConcurrentChatRuntimeTests-\(UUID().uuidString)",
			isDirectory: true
		).standardizedFileURL.resolvingSymlinksInPath()
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		defaults = try IsolatedUserDefaultsFixture(prefix: "ConcurrentChatRuntimeTests")
		service = ConcurrentChatService(checkout: project)
		let sessionID = UUID()
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(
				reference: WorkspaceLifecycleOwnerReference(
					owner: .source(sessionID: sessionID),
					workspace: WorkspaceIdentity(
						sessionID: sessionID,
						canonicalCheckoutPath: project.path
					)
				)
			),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: LocalStorage(defaults: defaults.defaults),
				reviewMarkerStore: ReviewMarkerStore(defaults: defaults.defaults),
				projectContextStore: ProjectContextStore(directory: project
					.appendingPathComponent("context"))
			)
		)
		fixture = WorkspaceTestFixture(store: store)
	}

	func cleanup()
	{
		service.releaseSuspendedOperations()
		fixture.shutdown()
		defaults.cleanup()
		try? FileManager.default.removeItem(at: project)
	}

	func select(_ threadID: String) async throws
	{
		let selection = try #require(fixture.inputs.selectThread(threadID))
		#expect(await selection.wait() == .finished)
		#expect(fixture.currentSnapshot.selectedThreadID == threadID)
	}

	func send(_ text: String) async throws
	{
		fixture.inputs.updateDraft(text)
		let submission = try #require(fixture.inputs.send())
		#expect(await submission.wait() == .finished)
	}

	func start(
		_ threadID: String,
		text: String
	) async throws
	{
		try await select(threadID)
		try await send(text)
		#expect(fixture.store.model.execution(for: .thread(threadID)).state == .running)
	}

	func stream(
		_ threadID: String,
		text: String
	)
	{
		let turnID = "\(threadID)-turn-1"
		service.turns[threadID] = (service.turns[threadID] ?? []).map
		{
			$0.id == turnID ? ConcurrentChatService.turn(
				turnID,
				text: text
			) : $0
		}
		service.emit(.agentMessageDelta(
			threadId: threadID,
			turnId: turnID,
			itemId: "answer",
			text: text
		))
	}

	func complete(
		_ threadID: String,
		status: String
	)
	{
		let turn = ConcurrentChatService.turn(
			"\(threadID)-turn-1",
			status: status
		)
		service.turns[threadID] = [turn]
		service.emit(.turnCompleted(
			threadId: threadID,
			turn: turn
		))
	}

	func completeLatest(
		_ threadID: String,
		status: String
	) throws
	{
		let latest = try #require(service.turns[threadID]?.last)
		let turn = ConcurrentChatService.turn(
			latest.id,
			status: status
		)
		service.turns[threadID] = [turn]
		service.emit(.turnCompleted(
			threadId: threadID,
			turn: turn
		))
	}

	func approval(_ threadID: String) -> PendingInteraction
	{
		PendingInteraction(
			id: "\(threadID)-approval",
			threadId: threadID,
			turnId: "\(threadID)-turn-1",
			itemId: "command",
			approvalId: nil,
			kind: .commandApproval,
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
}
