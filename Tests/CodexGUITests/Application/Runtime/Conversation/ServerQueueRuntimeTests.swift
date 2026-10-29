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
