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
		let harness = try ConcurrentChatFixture()
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
			let harness = try ConcurrentChatFixture()
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
		let harness = try ConcurrentChatFixture()
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
		let resumesBeforeReconnect = service.resumeDirectories.count
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
		let resumedThreads = service.resumeDirectories.dropFirst(resumesBeforeReconnect)
			.map(\.threadID)
		#expect(recoveredThreads == Set(["chat-a"]))
		#expect(resumedThreads == ["chat-b"])
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

}
