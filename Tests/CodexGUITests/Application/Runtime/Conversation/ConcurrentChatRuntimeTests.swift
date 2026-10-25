import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	.timeLimit(.minutes(1))
)
struct ConcurrentChatRuntimeTests
{

	@Test
	func retainedIntentTargetRespondsAndStopsCapturedOwnerWhileAnotherChatIsSelected() async throws
	{
		let harness = try Harness()
		defer
		{
			harness.cleanup()
		}
		let fixture = harness.fixture
		let service = harness.service
		await fixture.inputs.connect()
		try await harness.start(
			"chat-a",
			text: "Run A"
		)
		let capturedA = WorkspaceIntentTarget(
			store: fixture.store,
			snapshot: fixture.currentSnapshot
		)
		try await harness.start(
			"chat-b",
			text: "Run B"
		)
		var publicationCount = 0
		fixture.store.observePublications
		{
			publication in
			publicationCount += 1
			let snapshot = WorkspaceSelectors.snapshot(
				model: publication.model,
				now: fixture.store.now()
			)
			#expect(snapshot.selectedThreadID == "chat-b")
			#expect(publication.model.execution.activeThreadID == "chat-b")
			#expect(publication.model.execution.state == .running)
		}

		let approvalA = harness.approval("chat-a")
		service.emit(.interaction(approvalA))
		#expect(fixture.currentSnapshot.pendingInteractions.isEmpty)
		#expect(capturedA.dispatch(.respond(
			approvalA,
			.approval(.accept)
		)))
		let response = try #require(capturedA.operation)
		#expect(await response.wait() == .finished)
		#expect(service.responses == [approvalA.id])
		#expect(fixture.store.model.execution(for: .thread("chat-b")).pendingResponses.isEmpty)

		#expect(capturedA.dispatch(.stop))
		let interruption = try #require(capturedA.operation)
		#expect(await interruption.wait() == .finished)
		#expect(service.interruptions.map(\.threadID) == ["chat-a"])
		#expect(service.interruptions.map(\.turnID) == ["chat-a-turn-1"])
		#expect(fixture.store.model.execution(for: .thread("chat-a")).stopRequested)
		#expect(!fixture.store.model.execution(for: .thread("chat-b")).stopRequested)
		#expect(fixture.currentSnapshot.selectedThreadID == "chat-b")
		#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)
		harness.complete(
			"chat-a",
			status: "interrupted"
		)
		#expect(!capturedA.dispatch(.stop))
		#expect(service.interruptions.count == 1)
		#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)
		#expect(publicationCount > 1)
	}

	@Test
	func resumedConversationMismatchRejectsOnlyItsCapturedChat() async throws
	{
		for mismatch in ["thread", "checkout"]
		{
			let harness = try Harness()
			defer
			{
				harness.cleanup()
			}
			let fixture = harness.fixture
			let service = harness.service
			await fixture.inputs.connect()
			try await harness.start(
				"chat-b",
				text: "Keep B running"
			)
			try await harness.select("chat-a")
			let unexpectedSummary = ThreadSummary(json: [
				"id": mismatch == "thread" ? "chat-b" : "chat-a",
				"cwd": mismatch == "checkout"
					? harness.project.appendingPathComponent("other-checkout").path
					: harness.project.path,
				"status": ["type": "idle"],
			])!
			service.resumeOverrides["chat-a"] = ThreadDetail(
				summary: unexpectedSummary,
				turns: [],
				nextTurnsCursor: nil
			)
			fixture.inputs.updateDraft("Reject mismatched A")
			let rejected = try #require(fixture.inputs.send())
			if case .failed(let failure) = await rejected.wait()
			{
				#expect(!failure.outcomeIsUncertain)
			}
			else
			{
				Issue.record("Expected preparation to reject the returned conversation ownership.")
			}
			#expect(service.resumeDirectories.last?.threadID == "chat-a")
			#expect(service.resumeDirectories.last?.directory?.standardizedFileURL
				.resolvingSymlinksInPath().path == harness.project.path)
			#expect(service.starts.map(\.threadID) == ["chat-b"])
			#expect(fixture.currentSnapshot.draft == "Reject mismatched A")
			#expect(!fixture.store.model.execution(for: .thread("chat-a")).isTaskActive)
			#expect(!fixture.store.model.execution(for: .thread("chat-a")).hasUncertainRequest)
			#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)

			try await harness.select("chat-b")
			#expect(fixture.currentSnapshot.canSteer)
			let stoppingB = try #require(fixture.inputs.stop())
			#expect(await stoppingB.wait() == .finished)
			#expect(service.interruptions.map(\.threadID) == ["chat-b"])
			harness.complete(
				"chat-b",
				status: "interrupted"
			)
			try await harness.send("Continue B")
			#expect(service.starts.map(\.threadID) == ["chat-b", "chat-b"])
			#expect(service.starts.last?.turnID == "chat-b-turn-2")
			#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)
		}
	}

	@Test
	func backgroundCompletionPublishesAndReconnectReadsEveryOwnerWithoutResending() async throws
	{
		let harness = try Harness()
		defer
		{
			harness.cleanup()
		}
		let fixture = harness.fixture
		let service = harness.service
		await fixture.inputs.connect()
		try await harness.start(
			"chat-a",
			text: "A"
		)
		try await harness.start(
			"chat-b",
			text: "B"
		)
		let retiredEvent = try #require(service.onEvent)
		service.onDisconnect?("Fixture disconnect")
		#expect(fixture.store.model.execution(for: .thread("chat-a")).hasUncertainRequest)
		#expect(fixture.store.model.execution(for: .thread("chat-b")).hasUncertainRequest)
		let readsBeforeReconnect = service.reads.count
		await fixture.inputs.connect()
		let recoveryHandles = fixture.store.model.allExecutions.compactMap
		{
			$0.pendingReconciliation.flatMap
			{
				fixture.store.operation(for: $0.context)
			}
		}
		for handle in recoveryHandles
		{
			#expect(await handle.wait() == .finished)
		}
		let recoveredThreads = Set(service.reads.dropFirst(readsBeforeReconnect))
		#expect(recoveredThreads == Set(["chat-a", "chat-b"]))
		#expect(service.starts.count == 2)
		#expect(service.connectionCount == 2)
		#expect(fixture.store.model.execution(for: .thread("chat-a")).state == .running)
		#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)
		retiredEvent(.turnCompleted(
			threadId: "chat-a",
			turn: ConcurrentChatService.turn(
				"chat-a-turn-1",
				status: "completed"
			)
		))
		#expect(fixture.store.model.execution(for: .thread("chat-a")).state == .running)

		var completionCount = 0
		fixture.store.observePublications
		{
			publication in
			completionCount += publication.commands.filter
			{
				if case .taskFinished = $0
				{
					return true
				}
				return false
			}.count
		}
		harness.complete(
			"chat-a",
			status: "completed"
		)
		#expect(completionCount == 1)
		#expect(fixture.currentSnapshot.selectedThreadID == "chat-b")
		#expect(fixture.store.model.execution(for: .thread("chat-a")).state == .completed)
		#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .running)
		#expect(service.starts.count == 2)
	}

	@MainActor
	private final class Harness
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
}
