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
	func ordinaryChatsShareTransportAndRetainTheirOwnStreamsApprovalsAndDrafts() async throws
	{
		let harness = try Harness()
		defer
		{
			harness.cleanup()
		}
		let fixture = harness.fixture
		let service = harness.service
		let processIdentity = service.processIdentity
		service.turns["chat-a"] = [ConcurrentChatService.turn(
			"history-a",
			status: "completed",
			text: "Earlier A"
		)]
		service.turns["chat-b"] = [ConcurrentChatService.turn(
			"history-b",
			status: "completed",
			text: "Earlier B"
		)]
		await fixture.inputs.connect()
		try await harness.start(
			"chat-a",
			text: "Work on A"
		)
		fixture.inputs.updateDraft("Later instruction for A")
		let contextA = ComposerContextItem(
			kind: .textExcerpt,
			title: "A",
			excerpt: "Context A"
		)
		fixture.inputs.addDraftContext(contextA)

		try await harness.select("chat-b")
		#expect(fixture.currentSnapshot.canSend)
		try await harness.send("Work on B")
		fixture.inputs.updateDraft("Later instruction for B")
		let contextB = ComposerContextItem(
			kind: .textExcerpt,
			title: "B",
			excerpt: "Context B"
		)
		fixture.inputs.addDraftContext(contextB)
		#expect(service.connectionCount == 1)
		#expect(service.processIdentity == processIdentity)
		#expect(service.starts.map(\.threadID) == ["chat-a", "chat-b"])
		#expect(fixture.store.model.allExecutions.filter(\.isTaskActive).count == 2)
		#expect(fixture.store.model.identity.canonicalCheckoutPath == service.checkout.path)

		harness.stream(
			"chat-a",
			text: "A is working"
		)
		harness.stream(
			"chat-b",
			text: "B is working"
		)
		let approvalA = harness.approval("chat-a")
		let approvalB = harness.approval("chat-b")
		service.emit(.interaction(approvalA))
		service.emit(.interaction(approvalB))
		#expect(fixture.currentSnapshot.entries.last?.body == "B is working")
		#expect(fixture.currentSnapshot.pendingInteractions.map(\.id) == [approvalB.id])
		#expect(fixture.store.model.execution(for: .thread("chat-a")).pendingInteractions
			.map(\.id) == [approvalA.id])
		let response = try #require(fixture.inputs.respond(
			to: approvalA,
			with: .approval(.accept)
		))
		#expect(await response.wait() == .finished)
		#expect(service.responses == [approvalA.id])
		#expect(fixture.store.model.execution(for: .thread("chat-b")).pendingInteractions
			.map(\.id) == [approvalB.id])

		// A terminal notification for an older turn cannot finish the current owner.
		service.emit(.turnCompleted(
			threadId: "chat-a",
			turn: ConcurrentChatService.turn(
				"obsolete-a",
				status: "completed"
			)
		))
		#expect(fixture.store.model.execution(for: .thread("chat-a")).activeTurnID
			== "chat-a-turn-1")
		#expect(fixture.store.model.execution(for: .thread("chat-a")).isTaskActive)
		try await harness.select("chat-a")
		#expect(fixture.currentSnapshot.entries.last?.body == "A is working")
		#expect(fixture.currentSnapshot.draft == "Later instruction for A")
		#expect(fixture.currentSnapshot.draftContext == [contextA])
		try await harness.select("chat-b")
		#expect(fixture.currentSnapshot.draft == "Later instruction for B")
		#expect(fixture.currentSnapshot.draftContext == [contextB])
		#expect(fixture.currentSnapshot.entries.last?.body == "B is working")
		#expect(fixture.store.model.conversations.content[.thread("chat-a")]?.loadedTurns
			.map(\.id).contains("history-a") == true)
		#expect(fixture.store.model.conversations.content[.thread("chat-b")]?.loadedTurns
			.map(\.id).contains("history-b") == true)
	}

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
	func delayedPreparationStartsCapturedChatAfterAnotherChatStarts() async throws
	{
		let harness = try Harness()
		defer
		{
			harness.cleanup()
		}
		let fixture = harness.fixture
		let service = harness.service
		await fixture.inputs.connect()
		try await harness.select("chat-a")
		service.suspendedResumes.insert("chat-a")
		fixture.inputs.updateDraft("Delayed A")
		let delayedA = try #require(fixture.inputs.send())
		await service.waitForResume("chat-a")
		#expect(delayedA.completion == nil)

		try await harness.select("chat-b")
		try await harness.send("Immediate B")
		fixture.inputs.updateDraft("Keep B draft")
		service.finishResume("chat-a")
		#expect(await delayedA.wait() == .finished)
		#expect(service.starts.map(\.threadID) == ["chat-b", "chat-a"])
		#expect(service.starts.map(\.text) == ["Immediate B", "Delayed A"])
		#expect(fixture.currentSnapshot.selectedThreadID == "chat-b")
		#expect(fixture.currentSnapshot.draft == "Keep B draft")
		#expect(fixture.store.model.execution(for: .thread("chat-a")).activeTurnID
			== "chat-a-turn-1")
		#expect(fixture.store.model.execution(for: .thread("chat-b")).activeTurnID
			== "chat-b-turn-1")
		#expect(fixture.store.model.execution(for: delayedA.context)?.owner?.submission
			.requestID == delayedA.context.requestID)
	}

	@Test
	func steeringAndStopRemainIndependentAcrossNavigation() async throws
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
			text: "First A"
		)
		try await harness.start(
			"chat-b",
			text: "First B"
		)
		try await harness.select("chat-a")
		service.suspendedSteering.insert("chat-a")
		fixture.inputs.steer("Steer A")
		await service.waitForSteering("chat-a")
		let pendingA = try #require(fixture.store.model.execution(for: .thread("chat-a"))
			.pendingSteering)
		let steeringA = try #require(fixture.store.operation(for: pendingA))

		try await harness.select("chat-b")
		service.suspendedSteering.insert("chat-b")
		fixture.inputs.steer("Steer B")
		await service.waitForSteering("chat-b")
		let pendingB = try #require(fixture.store.model.execution(for: .thread("chat-b"))
			.pendingSteering)
		let steeringB = try #require(fixture.store.operation(for: pendingB))
		service.finishSteering("chat-b")
		#expect(await steeringB.wait() == .finished)
		let stoppingB = try #require(fixture.inputs.stop())
		#expect(await stoppingB.wait() == .finished)
		#expect(service.interruptions.map(\.threadID) == ["chat-b"])
		#expect(service.interruptions.map(\.turnID) == ["chat-b-turn-1"])
		#expect(fixture.store.model.execution(for: .thread("chat-a")).pendingSteering == pendingA)
		#expect(!fixture.store.model.execution(for: .thread("chat-a")).stopRequested)
		#expect(fixture.store.model.execution(for: .thread("chat-a")).state == .running)

		service.finishSteering("chat-a")
		#expect(await steeringA.wait() == .finished)
		#expect(service.steering.map(\.threadID) == ["chat-a", "chat-b"])
		#expect(service.steering.map(\.turnID) == ["chat-a-turn-1", "chat-b-turn-1"])
		#expect(service.steering.map(\.text) == ["Steer A", "Steer B"])
		harness.complete(
			"chat-b",
			status: "interrupted"
		)
		#expect(fixture.store.model.execution(for: .thread("chat-b")).state == .stopped)
		#expect(fixture.store.model.execution(for: .thread("chat-a")).state == .running)
		try await harness.select("chat-a")
		let stoppingA = try #require(fixture.inputs.stop())
		#expect(await stoppingA.wait() == .finished)
		#expect(service.interruptions.map(\.threadID) == ["chat-b", "chat-a"])
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
