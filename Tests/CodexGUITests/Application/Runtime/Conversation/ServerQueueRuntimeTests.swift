import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ServerQueueRuntimeTests
{
	@Test func serverDispatchesFollowUpsAndResumeWithoutALocalCompetingDispatcher() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(
			harness,
			queued: ["A", "B"]
		)
		#expect(harness.service.starts.map(\.text) == ["First"])
		#expect(harness.fixture.store.model.composer.automaticQueueConversations.isEmpty)
		harness.complete(
			"chat-a",
			status: "completed"
		)
		try await wait(harness)
		{
			harness.service.starts.count == 2 && harness.fixture.currentSnapshot.queuedMessages
				.map(\.text) == ["B"]
		}
		#expect(harness.service.starts.map(\.text) == ["First", "A"])
		try harness.completeLatest(
			"chat-a",
			status: "interrupted"
		)
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuePaused)
		#expect(harness.fixture.currentSnapshot.canResumeQueue)
		harness.fixture.inputs.updateDraft("Keep newer draft")
		let operation = try #require(harness.fixture.inputs.resumeMessageQueue())
		#expect(await operation.wait() == .finished)
		try await settled(harness)
		#expect(harness.service.starts.map(\.text) == ["First", "A", "B"])
		#expect(harness.fixture.currentSnapshot.draft == "Keep newer draft")
		#expect(harness.fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(harness.fixture.store.model.composer.automaticQueueConversations.isEmpty)
		try await harness.fixture.store.drainPersistence()
	}

	@Test func serverEditsReorderingAndDeletionKeepServerAndClientIdentity() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(
			harness,
			queued: ["A", "B", "C"]
		)
		let original = harness.fixture.currentSnapshot.queuedMessages
		let edited = original[1]
		harness.fixture.inputs.beginEditingQueuedMessage(edited)
		harness.fixture.inputs.updateDraft("Revised B")
		let update = try #require(harness.fixture.inputs.send())
		#expect(await update.wait() == .finished)
		try await settled(harness)
		let messages = harness.fixture.currentSnapshot.queuedMessages
		#expect(messages.map(\.text) == ["A", "Revised B", "C"])
		#expect(messages[1].id == edited.id)
		#expect(messages[1].serverID == edited.serverID)
		harness.fixture.inputs.reorderQueuedMessages([original[2].id, edited.id, original[0].id])
		try await wait(harness)
		{
			harness.fixture.currentSnapshot.queuedMessages.first?.id == original[2].id
		}
		try await settled(harness)
		harness.fixture.inputs.removeQueuedMessage(
			edited.id,
			editing: false
		)
		try await wait(harness)
		{
			harness.fixture.currentSnapshot.queuedMessages.count == 2
		}
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuedMessages.map(\.text) == ["C", "A"])
		#expect(harness.service.serverQueue["chat-a"]?.map(\.localID) == [
			original[2].id,
			original[0].id
		])
		#expect(harness.fixture.currentSnapshot.canSteerQueuedMessage)
		let steering = try #require(harness.fixture.inputs.steerQueuedMessage(original[0].id))
		#expect(await steering.wait() == .finished)
		try await settled(harness)
		#expect(harness.service.steering.map(\.text) == ["A"])
		#expect(harness.fixture.currentSnapshot.queuedMessages.map(\.text) == ["C"])
		#expect(harness.service.serverQueue["chat-a"]?.map(\.preview) == ["C"])
		try harness.completeLatest(
			"chat-a",
			status: "completed"
		)
		try await wait(harness)
		{
			harness.service.starts.count == 2
		}
		#expect(harness.service.starts.map(\.text) == ["First", "C"])
		try await harness.fixture.store.drainPersistence()
	}

	@Test func invalidatedPaginatedReadCannotPublishStaleQueueOrChangeSelectedConversation(
	) async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.service.serverQueueReadGate?.signal(); harness.cleanup()
		}
		harness.service.queueAPISupported = true
		harness.service.serverQueue["chat-a"] = [try entry("A"), try entry("B")]
		let gate = RuntimeSignal()
		harness.service.serverQueueReadGate = gate
		defer
		{
			gate.signal()
		}
		await harness.fixture.inputs.connect()
		try await harness.select("chat-a")
		await harness.service.serverQueueReadStarted.wait()
		let latest = try entry("Latest")
		harness.service.serverQueue["chat-a"] = [latest]
		var observedQueues: [[String]] = []
		let observer = harness.fixture.store.observePublications
		{
			_ in
			observedQueues
				.append(harness.fixture.store.model.composer.drafts[.thread("chat-a")]?
					.queuedMessages.map(\.text) ?? [])
		}
		defer
		{
			harness.fixture.store.removePublicationObserver(observer)
		}
		harness.service.emit(.threadQueueChanged(threadId: "chat-a"))
		try await harness.select("chat-b")
		gate.signal()
		try await wait(harness)
		{
			harness.fixture.store.model.composer.drafts[.thread("chat-a")]?.queuedMessages
				.map(\.text) == ["Latest"]
		}
		#expect(!observedQueues.isEmpty)
		#expect(observedQueues.allSatisfy
		{
			$0.isEmpty || $0 == ["Latest"]
		})
		#expect(harness.fixture.currentSnapshot.selectedThreadID == "chat-b")
		#expect(harness.fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(harness.fixture.store.model.composer.drafts[.thread("chat-a")]?.queuePaused == true)
		#expect(harness.service.serverQueueCalls.filter
		{
			$0 == "list:chat-a:head"
		}.count >= 2)
		try await harness.fixture.store.drainPersistence()
	}

	@Test func uncertainAddIsNotReplayedAndAuthoritativeClientIDResolvesIt() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(harness)
		harness.service.serverQueueFailure = AppServerError.disconnected
		harness.fixture.inputs.updateDraft("Possibly accepted")
		let add = try #require(harness.fixture.inputs.send())
		guard case .failed(let failure) = await add.wait()
		else
		{
			Issue.record("Expected uncertain queue write"); return
		}
		#expect(failure.outcomeIsUncertain)
		let held = try #require(harness.fixture.currentSnapshot.queuedMessages.first)
		#expect(held.enqueueUncertain == true)
		#expect(harness.fixture.currentSnapshot.draft == "Possibly accepted")
		#expect(harness.fixture.inputs.send() == nil)
		try harness.completeLatest(
			"chat-a",
			status: "interrupted"
		)
		#expect(harness.fixture.inputs.resumeMessageQueue() == nil)
		harness.service.serverQueueFailure = nil
		harness.service.serverQueue["chat-a"] = [try entry(
			"Possibly accepted",
			clientID: held.id.uuidString
		)]
		harness.service.emit(.threadQueueChanged(threadId: "chat-a"))
		try await wait(harness)
		{
			harness.fixture.currentSnapshot.queuedMessages.first?.serverID != nil
		}
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.canResumeQueue)
		#expect(harness.service.serverQueueCalls.filter
		{
			$0.hasPrefix("add:")
		}.count == 1)
		let resume = try #require(harness.fixture.inputs.resumeMessageQueue())
		#expect(await resume.wait() == .finished)
		try await settled(harness)
		#expect(harness.service.starts.map(\.text) == ["First", "Possibly accepted"])
		try await harness.fixture.store.drainPersistence()
	}

	@Test func unsupportedReadFallsBackToLocalQueueWithoutServerWrites() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		harness.service.serverQueueFailure = ThreadQueueUnsupported()
		await harness.fixture.inputs.connect()
		try await harness.select("chat-a")
		try await wait(harness)
		{
			harness.fixture.store.model.composer.serverQueues[.thread("chat-a")]?
				.authority == .local
		}
		try await harness.send("First")
		harness.fixture.inputs.updateDraft("Local fallback")
		harness.fixture.inputs.send()
		#expect(harness.fixture.currentSnapshot.queuedMessages.map(\.text) == ["Local fallback"])
		#expect(!harness.service.serverQueueCalls.contains
		{
			$0.hasPrefix("add:")
		})
		try await harness.fixture.store.drainPersistence()
	}

	@Test func checkoutMismatchRejectsMutationBeforeTheQueueRPC() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(harness)
		harness.service.readOverrides["chat-a"] = ThreadDetail(
			summary: ThreadSummary(json: ["id": "chat-a", "cwd": "/foreign-checkout"])!,
			turns: [],
			nextTurnsCursor: nil
		)
		harness.fixture.inputs.updateDraft("Keep my input")
		let request = try #require(harness.fixture.inputs.send())
		guard case .failed(let failure) = await request.wait()
		else
		{
			Issue.record("Expected ownership failure"); return
		}
		#expect(!failure.outcomeIsUncertain)
		#expect(harness.fixture.currentSnapshot.draft == "Keep my input")
		#expect(harness.fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(!harness.service.serverQueueCalls.contains
		{
			$0.hasPrefix("add:")
		})
		try await harness.fixture.store.drainPersistence()
	}

	@Test func legacyQueueMigratesOnlyAfterExplicitResumeAndRetainsIdentity() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		let messages = ["Legacy A", "Legacy B"].map
		{
			text in
			QueuedComposerMessage(
				id: UUID(),
				text: text,
				context: [],
				modelID: "captured-model",
				effort: "high",
				preferences: .standard,
				skills: [],
				collaborationMode: nil,
				serviceTier: nil
			)
		}
		harness.fixture.draftStorage.saveQueuedMessages(
			messages,
			for: harness.project,
			threadID: "chat-a"
		)
		await harness.fixture.inputs.connect()
		try await harness.select("chat-a")
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuePaused)
		#expect(harness.service.starts.isEmpty)
		#expect(!harness.service.serverQueueCalls.contains
		{
			$0.hasPrefix("add:")
		})
		harness.fixture.inputs.updateDraft("Keep this draft")
		let resume = try #require(harness.fixture.inputs.resumeMessageQueue())
		#expect(await resume.wait() == .finished)
		try await settled(harness)
		#expect(harness.service.starts.map(\.text) == ["Legacy A"])
		#expect(harness.fixture.currentSnapshot.queuedMessages.map(\.id) == [messages[1].id])
		#expect(harness.fixture.currentSnapshot.queuedMessages.first?.modelID == "captured-model")
		#expect(harness.fixture.currentSnapshot.draft == "Keep this draft")
		#expect(harness.service.serverQueueCalls.filter
		{
			$0.hasPrefix("add:")
		}.count == 2)
		try await harness.fixture.store.drainPersistence()
	}

	@Test func restoredUncertainAcceptanceWaitsForProofWithoutResubmitting() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		var message = QueuedComposerMessage(
			id: UUID(),
			text: "Unacknowledged",
			context: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			skills: [],
			collaborationMode: nil,
			serviceTier: nil
		)
		message.enqueueUncertain = true
		harness.fixture.draftStorage.saveQueuedMessages(
			[message],
			for: harness.project,
			threadID: "chat-a"
		)
		await harness.fixture.inputs.connect()
		try await harness.select("chat-a")
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuedMessages == [message])
		#expect(harness.fixture.inputs.resumeMessageQueue() == nil)
		#expect(harness.service.starts.isEmpty)
		let accepted = try entry(
			"Unacknowledged",
			clientID: message.id.uuidString
		)
		harness.service.serverQueue["chat-a"] = [accepted]
		harness.service.emit(.threadQueueChanged(threadId: "chat-a"))
		try await wait(harness)
		{
			harness.fixture.currentSnapshot.queuedMessages.first?.serverID == accepted.id
		}
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.canResumeQueue)
		#expect(!harness.service.serverQueueCalls.contains
		{
			$0.hasPrefix("add:")
		})
		try await harness.fixture.store.drainPersistence()
	}

	@Test(arguments: ["deleteMissing", "deleteLostReply", "steerRejected", "steerLostReply"])
	func steeringFailuresNeverReplayTheDetachedInput(_ scenario: String) async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(
			harness,
			queued: ["Only once"]
		)
		let message = try #require(harness.fixture.currentSnapshot.queuedMessages.first)
		switch scenario
		{
		case "deleteMissing": harness.service.serverQueueDeleteMissing = true
		case "deleteLostReply": harness.service
			.serverQueueDeleteFailureAfterRemoval = AppServerError.disconnected
		case "steerRejected": harness.service.serverQueueSteerFailure = AppServerError
			.requestRejected("Turn ended")
		default: harness.service.serverQueueSteerFailure = AppServerError.disconnected
		}
		let operation = try #require(harness.fixture.inputs.steerQueuedMessage(message.id))
		guard case .failed = await operation.wait()
		else
		{
			Issue.record("Expected steering failure"); return
		}
		try await settled(harness)
		let held = try #require(harness.fixture.currentSnapshot.queuedMessages.first)
		#expect(held.id == message.id)
		#expect(held.serverID == nil)
		#expect(held.enqueueUncertain == (scenario != "steerRejected"))
		#expect(harness.service.steering.count == (scenario.hasPrefix("delete") ? 0 : 1))
		#expect(harness.service.serverQueue["chat-a"]?.isEmpty == true)
		#expect(harness.fixture.inputs.steerQueuedMessage(message.id) == nil)
		try harness.completeLatest(
			"chat-a",
			status: "interrupted"
		)
		try await settled(harness)
		if scenario !=
			"steerRejected"
		{
			#expect(harness.fixture.inputs.resumeMessageQueue() == nil)
		}
		#expect(harness.service.starts.map(\.text) == ["First"])
		#expect(harness.service.serverQueueCalls.filter
		{
			$0.hasPrefix("add:")
		}.count == 1)
		try await harness.fixture.store.drainPersistence()
		#expect(harness.fixture.draftStorage
			.queuedMessages(
				for: harness.project,
				threadID: "chat-a"
			).first?.steeringPhase == held
			.steeringPhase)
	}

	@Test func queuedSteeringPersistsBeforeSendingAndRejectsDoubleClicks() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(
			harness,
			queued: ["Only once"]
		)
		let message = try #require(harness.fixture.currentSnapshot.queuedMessages.first)
		let old = try #require(harness.service.serverQueue["chat-a"]?.first)
		let entry = try ThreadQueuedSubmission(json: [
			"id": old.id,
			"clientUserMessageId": old.clientUserMessageID,
			"input": old.input + [["type": "image", "url": "https://example.invalid/image.png"]]
		])
		harness.service.serverQueue["chat-a"] = [entry]
		harness.service.emit(.threadQueueChanged(threadId: "chat-a"))
		try await settled(harness)
		harness.service.suspendedSteering.insert("chat-a")
		harness.service.queueCheckpoint = ("delete", false)
		let operation = try #require(harness.fixture.inputs.steerQueuedMessage(message.id))
		await harness.service.queueCheckpointReached.wait()
		let deleting = try #require(harness.fixture.draftStorage.queuedMessages(
			for: harness.project,
			threadID: "chat-a"
		).first)
		#expect(deleting.steeringPhase == .deleting)
		#expect(deleting.serverID == entry.id)
		#expect(deleting.enqueueUncertain == true)
		#expect(harness.service.serverQueue["chat-a"] == [entry])
		#expect(harness.service.serverQueueSteeredInputs.isEmpty)
		harness.service.queueCheckpointRelease.signal()
		await harness.service.waitForSteering("chat-a")
		#expect(harness.fixture.inputs.steerQueuedMessage(message.id) == nil)
		#expect(harness.service.serverQueue["chat-a"]?.isEmpty == true)
		#expect(harness.service.serverQueueSteeredInputs == [entry.inputJSON])
		let persisted = try #require(harness.fixture.draftStorage.queuedMessages(
			for: harness.project,
			threadID: "chat-a"
		).first)
		#expect(persisted.steeringPhase == .sending)
		#expect(persisted.enqueueUncertain == true)
		#expect(persisted.serverID == nil)
		harness.service.finishSteering("chat-a")
		#expect(await operation.wait() == .finished)
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(harness.service.steering.count == 1)
		let delete = try #require(harness.service.serverQueueCalls
			.firstIndex
			{
				$0.hasPrefix("delete:")
			})
		let steer = try #require(harness.service.serverQueueCalls
			.firstIndex
			{
				$0.hasPrefix("steer:")
			})
		#expect(delete < steer)
		try await harness.fixture.store.drainPersistence()
	}

	@Test(arguments: [QueuedComposerMessage.SteeringPhase.deleting, .sending])
	func restoredSteeringJournalCannotBecomeAFreshSubmission(_ phase: QueuedComposerMessage
		.SteeringPhase) async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		var message = QueuedComposerMessage(
			id: UUID(),
			text: "Uncertain handoff",
			context: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			skills: [],
			collaborationMode: nil,
			serviceTier: nil
		)
		message.serverID = phase == .deleting ? "deleted-entry" : nil
		message.steeringPhase = phase
		message.enqueueUncertain = true
		harness.fixture.draftStorage.saveQueuedMessages(
			[message],
			for: harness.project,
			threadID: "chat-a"
		)
		await harness.fixture.inputs.connect()
		try await harness.select("chat-a")
		try await settled(harness)
		#expect(harness.fixture.currentSnapshot.queuedMessages.first?.id == message.id)
		#expect(harness.fixture.inputs.resumeMessageQueue() == nil)
		#expect(harness.fixture.inputs.steerQueuedMessage(message.id) == nil)
		#expect(harness.service.starts.isEmpty)
		#expect(harness.service.steering.isEmpty)
		#expect(!harness.service.serverQueueCalls.contains
		{
			$0.hasPrefix("add:")
		})
		try await harness.fixture.store.drainPersistence()
	}

	@Test(
		arguments: ["add", "update", "delete", "steer"],
		[false, true]
	)
	func retiredQueueMutationsIgnoreLateReplies(
		command: String,
		shutdown: Bool
	) async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		harness.service.queueAPISupported = true
		try await start(
			harness,
			queued: ["Original"]
		)
		let original = try #require(harness.fixture.currentSnapshot.queuedMessages.first)
		let priorCalls = harness.service.serverQueueCalls.filter
		{
			$0.hasPrefix(command + ":")
		}
		.count
		harness.service.queueCheckpoint = (command, true)
		let operation: WorkspaceOperationHandle
		switch command
		{
		case "add":
			harness.fixture.inputs.updateDraft("New entry")
			operation = try #require(harness.fixture.inputs.send())
		case "update":
			harness.fixture.inputs.beginEditingQueuedMessage(original)
			harness.fixture.inputs.updateDraft("Edited entry")
			operation = try #require(harness.fixture.inputs.send())
		case "delete":
			operation = try #require(harness.fixture.inputs
				.requestServerQueue(.delete(original.id)))
		default:
			operation = try #require(harness.fixture.inputs.steerQueuedMessage(original.id))
		}
		await harness.service.queueCheckpointReached.wait()
		switch command
		{
		case "add": #expect(harness.service.serverQueue["chat-a"]?.map(\.preview) == [
				"Original",
				"New entry"
			])
		case "update": #expect(harness.service.serverQueue["chat-a"]?
				.map(\.preview) == ["Edited entry"])
		default: #expect(harness.service.serverQueue["chat-a"]?.isEmpty == true)
		}
		let tasks = harness.fixture.store.executionTasks(for: operation.context)
		#expect(!tasks.isEmpty)
		if shutdown
		{
			harness.fixture.shutdown()
		}
		else
		{
			harness.service.onDisconnect?("connection lost")
		}
		let retiredDraft = harness.fixture.store.model.composer.drafts[.thread("chat-a")]
		let retiredExecution = harness.fixture.store.model.execution(for: .thread("chat-a"))
		var publications: [WorkspaceModel] = []
		let observer = harness.fixture.store.observePublications
		{
			publications.append($0.model)
		}
		defer
		{
			harness.fixture.store.removePublicationObserver(observer)
		}
		harness.service.queueCheckpointRelease.signal()
		for task in tasks
		{
			await task.value
		}
		#expect(await operation.wait() == (shutdown ? .cancelled : .finished))
		try await harness.fixture.store.drainPersistence()
		#expect(harness.fixture.store.model.composer.drafts[.thread("chat-a")] == retiredDraft)
		let afterReply = harness.fixture.store.model.execution(for: .thread("chat-a"))
		#expect(afterReply.state == retiredExecution.state)
		#expect(afterReply.activeTurnID == retiredExecution.activeTurnID)
		// A disconnected transport may retire its own pending handle without accepting its reply.
		let expectedSteering = command == "steer" && !shutdown
			? nil : retiredExecution.pendingSteering
		#expect(afterReply.pendingSteering == expectedSteering)
		#expect(afterReply.needsReconciliation == retiredExecution.needsReconciliation)
		#expect(afterReply.hasUncertainRequest == retiredExecution.hasUncertainRequest)
		#expect(publications.isEmpty == shutdown)
		for published in publications
		{
			#expect(published.composer.drafts[.thread("chat-a")] == retiredDraft)
			let execution = published.execution(for: .thread("chat-a"))
			#expect(execution.state == retiredExecution.state)
			#expect(execution.activeTurnID == retiredExecution.activeTurnID)
			#expect(execution.needsReconciliation == retiredExecution.needsReconciliation)
			#expect(execution.hasUncertainRequest == retiredExecution.hasUncertainRequest)
			#expect(execution.pendingSteering == retiredExecution.pendingSteering ||
				execution.pendingSteering == expectedSteering)
		}
		#expect(harness.fixture.draftStorage.queuedMessages(
			for: harness.project,
			threadID: "chat-a"
		) == retiredDraft?.queuedMessages ?? [])
		#expect(harness.fixture.draftStorage.queuedMessageEdit(
			for: harness.project,
			threadID: "chat-a"
		) == retiredDraft?.queuedMessageEdit)
		#expect(harness.service.starts.map(\.text) == ["First"])
		#expect(harness.service.serverQueueCalls.filter
		{
			$0.hasPrefix(command + ":")
		}.count == priorCalls + 1)
		if command == "steer"
		{
			#expect(harness.service.steering.count == 1)
		}
	}

	private func start(
		_ harness: ConcurrentChatFixture,
		queued messages: [String] = []
	) async throws
	{
		await harness.fixture.inputs.connect()
		try await harness.start(
			"chat-a",
			text: "First"
		)
		try await settled(harness)
		try #require(harness.fixture.store.model.composer.serverQueues[.thread("chat-a")]?
			.authority == .server)
		for text in messages
		{
			try await add(
				text,
				harness
			)
		}
	}

	private func add(
		_ text: String,
		_ harness: ConcurrentChatFixture
	) async throws
	{
		harness.fixture.inputs.updateDraft(text)
		let operation = try #require(harness.fixture.inputs.send())
		#expect(await operation.wait() == .finished)
		try await settled(harness)
	}

	private func entry(
		_ text: String,
		clientID: String = UUID().uuidString
	) throws -> ThreadQueuedSubmission
	{
		try ThreadQueuedSubmission(json: [
			"id": UUID().uuidString,
			"clientUserMessageId": clientID,
			"input": [["type": "text", "text": text, "text_elements": []]]
		])
	}

	private func settled(_ harness: ConcurrentChatFixture) async throws
	{
		try await wait(harness)
		{
			guard let state = harness.fixture.store.model.composer.serverQueues[.thread("chat-a")]
			else
			{
				return false
			}
			return state.pending == nil && !state.needsRefresh
		}
	}

	private func wait(
		_ harness: ConcurrentChatFixture,
		until predicate: @escaping @MainActor () -> Bool
	) async throws
	{
		if predicate()
		{
			return
		}
		let signal = RuntimeSignal()
		let id = harness.fixture.store
			.observePublications
			{
				_ in if predicate()
				{
					signal.signal()
				}
			}
		defer
		{
			harness.fixture.store.removePublicationObserver(id)
		}
		await signal.wait()
	}
}
