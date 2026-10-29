import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ComposerQueueRuntimeTests
{
	@Test func followUpsRunInOrderInTheirOriginalChatAndPreserveNewDraft() async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		let fixture = harness.fixture
		await fixture.inputs.connect()
		try await harness.select("chat-a")
		#expect(!fixture.currentSnapshot.canQueue)
		fixture.inputs.updateDraft("First")
		let initial = try #require(fixture.inputs.send())
		#expect(fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(await initial.wait() == .finished)
		#expect(harness.service.starts.map(\.text) == ["First"])
		#expect(fixture.currentSnapshot.queuedMessages.isEmpty)
		#expect(fixture.currentSnapshot.canQueue)
		var preparing = fixture.store.model
		preparing.execution.activeTurnID = nil
		#expect(!WorkspaceEligibility(model: preparing).canQueue)
		fixture.inputs.updateDraft("Second")
		fixture.inputs.send()
		#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Second"])
		#expect(harness.service.starts.count == 1)
		fixture.inputs.updateDraft("Third")
		fixture.inputs.send()
		fixture.inputs.updateDraft("Unsent fourth")
		fixture.inputs.selectApprovalMode(.fullAccess)
		#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Second", "Third"])
		#expect(harness.service.starts.map(\.text) == ["First"])
		#expect(harness.service.steering.isEmpty)
		try await fixture.store.drainPersistence()
		#expect(fixture.draftStorage.queuedMessages(
			for: harness.project,
			threadID: "chat-a"
		)
		.map(\.text) == [
			"Second",
			"Third"
		])

		let staleStop = OperationContext(
			workspace: fixture.store.model.identity,
			generation: fixture.store.model.connection.generation - 1,
			requestID: UUID(),
			threadID: "chat-a"
		)
		fixture.store.dispatch(.execution(.stopRequested(
			staleStop,
			ownerRequestID: fixture.store.model
				.execution.owner?.submission.requestID
		)))
		#expect(fixture.store.model.composer.automaticQueueConversations
			.contains(.thread("chat-a")))
		try await harness.select("chat-b")
		harness.complete(
			"chat-a",
			status: "completed"
		)
		try await waitForQueueCount(
			1,
			conversation: .thread("chat-a"),
			store: fixture.store
		)
		#expect(harness.service.starts.map(\.text) == ["First", "Second"])
		#expect(harness.service.starts.map(\.threadID) == ["chat-a", "chat-a"])
		#expect(fixture.currentSnapshot.selectedThreadID == "chat-b")
		try harness.completeLatest(
			"chat-a",
			status: "completed"
		)
		try await waitForQueueCount(
			0,
			conversation: .thread("chat-a"),
			store: fixture.store
		)
		#expect(harness.service.starts.map(\.text) == ["First", "Second", "Third"])
		#expect(harness.service.submittedPreferences == [.standard, .standard, .standard])
		#expect(fixture.store.model.composer.drafts[.thread("chat-a")]?.text == "Unsent fourth")
		try await fixture.store.drainPersistence()
		#expect(fixture.draftStorage.queuedMessages(
			for: harness.project,
			threadID: "chat-a"
		)
		.isEmpty)
	}

	@Test(arguments: ["interrupted", "failed"])
	func interruptedOrFailedTurnPreservesQueueUntilExplicitResume(status: String) async throws
	{
		try await withStartedQueue(["Later"])
		{
			harness in
			let fixture = harness.fixture
			harness.complete(
				"chat-a",
				status: status
			)
			#expect(harness.service.starts.count == 1)
			#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Later"])
			#expect(fixture.currentSnapshot.queuePaused)
			#expect(fixture.currentSnapshot.canResumeQueue)
			#expect(fixture.store.model.composer.automaticQueueConversations.isEmpty)
			fixture.inputs.updateDraft("Keep this newer draft")
			let resume = try #require(fixture.inputs.resumeMessageQueue())
			#expect(await resume.wait() == .finished)
			#expect(harness.service.starts.map(\.text) == ["First", "Later"])
			#expect(fixture.currentSnapshot.queuedMessages.isEmpty)
			#expect(!fixture.currentSnapshot.queuePaused)
			#expect(fixture.currentSnapshot.draft == "Keep this newer draft")
			#expect(fixture.inputs.resumeMessageQueue() == nil)

			try await fixture.store.drainPersistence()
		}
	}

	@Test func disconnectAndRelaunchKeepQueuePausedWithoutAutomaticReplay() async throws
	{
		try await withStartedQueue(["Saved follow up"])
		{
			harness in
			let fixture = harness.fixture
			try await fixture.store.drainPersistence()
			let oldQueue = fixture.currentSnapshot.queuedMessages
			harness.service.onDisconnect?("connection lost")
			#expect(fixture.currentSnapshot.queuedMessages == oldQueue)
			#expect(fixture.currentSnapshot.queuePaused)
			#expect(!fixture.currentSnapshot.canResumeQueue)
			#expect(fixture.inputs.resumeMessageQueue() == nil)
			#expect(fixture.store.model.composer.automaticQueueConversations.isEmpty)
			harness.complete(
				"chat-a",
				status: "completed"
			)
			#expect(harness.service.starts.count == 1)
			try await fixture.store.drainPersistence()
			fixture.shutdown()
			fixture.draftStorage.saveQueuedMessages(
				oldQueue,
				for: harness.project,
				threadID: "chat-a"
			)
			let store = makeRestoredStore(harness)
			let restored = WorkspaceTestFixture(store: store)
			defer
			{
				restored.shutdown()
			}
			await restored.inputs.connect()
			let selection = try #require(restored.inputs.selectThread("chat-a"))
			#expect(await selection.wait() == .finished)
			#expect(restored.currentSnapshot.queuedMessages == oldQueue)
			#expect(restored.currentSnapshot.queuePaused)
			#expect(restored.store.model.composer.automaticQueueConversations.isEmpty)
			harness.complete(
				"chat-a",
				status: "completed"
			)
			#expect(harness.service.starts.count == 1)
			let resume = try #require(restored.inputs.resumeMessageQueue())
			#expect(await resume.wait() == .finished)
			#expect(harness.service.starts.map(\.text) == ["First", "Saved follow up"])
			try await store.drainPersistence()
		}
	}

	@Test func reorderAndEditKeepIdentityAttachmentsAndNewerDraft() async throws
	{
		try await withStartedQueue([])
		{
			harness in
			let fixture = harness.fixture
			fixture.inputs.updateDraft("Queued A")
			let item = ComposerContextItem(
				kind: .textExcerpt,
				title: "Code",
				path: "file.swift",
				excerpt: "let x = 1"
			)
			fixture.inputs.addDraftContext(item)
			fixture.inputs.send()
			fixture.inputs.updateDraft("Queued B")
			fixture.inputs.send()
			let messages = fixture.currentSnapshot.queuedMessages
			let first = try #require(messages.first)
			let last = try #require(messages.last)
			fixture.inputs.updateDraft("Keep draft")
			fixture.inputs.reorderQueuedMessages([last.id, first.id])
			fixture.inputs.reorderQueuedMessages([last.id, last.id])

			fixture.inputs.removeQueuedMessage(
				first.id,
				editing: true
			)
			#expect(fixture.currentSnapshot.draft == "Keep draft")
			#expect(!fixture.currentSnapshot.isEditingQueuedMessage)
			#expect(fixture.currentSnapshot.queuedMessages == [last, first])
			fixture.inputs.updateDraft("")
			fixture.inputs.removeQueuedMessage(
				first.id,
				editing: true
			)
			#expect(fixture.currentSnapshot.queuedMessages == [last])
			#expect(fixture.currentSnapshot.draft == "Queued A")
			#expect(fixture.currentSnapshot.draftContext == [item])
			fixture.inputs.updateDraft("Edited A")
			fixture.inputs.send()
			fixture.inputs.beginEditingQueuedMessage(first)
			#expect(fixture.currentSnapshot.queuedMessages.map(\.id) == [last.id, first.id])
			#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Queued B", "Edited A"])
			#expect(fixture.currentSnapshot.queuedMessages.last?.context == [item])
			#expect(fixture.currentSnapshot.draft.isEmpty)
			#expect(!fixture.currentSnapshot.isEditingQueuedMessage)

			try await fixture.store.drainPersistence()
			#expect(fixture.draftStorage
				.queuedMessages(
					for: harness.project,
					threadID: "chat-a"
				) == fixture.currentSnapshot
				.queuedMessages)
			for message in fixture.currentSnapshot.queuedMessages
			{
				fixture.inputs.removeQueuedMessage(
					message.id,
					editing: false
				)
			}
			#expect(fixture.currentSnapshot.queuedMessages.isEmpty)
			try await fixture.store.drainPersistence()
			#expect(fixture.draftStorage.queuedMessages(
				for: harness.project,
				threadID: "chat-a"
			)
			.isEmpty)
		}
	}

	@Test func steeringChosenQueuedMessagePreservesOtherEntriesAndComposerDuringReservation(
	) async throws
	{
		try await withStartedQueue(["Queued A", "Queued B"])
		{
			harness in
			let fixture = harness.fixture
			let messages = fixture.currentSnapshot.queuedMessages
			let last = try #require(messages.last)
			fixture.inputs.updateDraft("Unsent draft")
			harness.service.suspendedSteering.insert("chat-a")
			let operation = try #require(fixture.inputs.steerQueuedMessage(last.id))
			await harness.service.waitForSteering("chat-a")
			fixture.inputs.removeQueuedMessage(
				last.id,
				editing: false
			)
			fixture.inputs.reorderQueuedMessages(messages.reversed().map(\.id))

			fixture.inputs.updateDraft("")
			fixture.inputs.beginEditingQueuedMessage(last)
			#expect(!fixture.currentSnapshot.isEditingQueuedMessage)
			fixture.inputs.updateDraft("Unsent draft")

			#expect(fixture.currentSnapshot.queuedMessages == messages)
			harness.service.finishSteering("chat-a")
			#expect(await operation.wait() == .finished)
			#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Queued A"])
			#expect(fixture.currentSnapshot.draft == "Unsent draft")
			#expect(harness.service.steering.map(\.text) == ["Queued B"])
			#expect(harness.service.starts.count == 1)
			try await fixture.store.drainPersistence()
		}
	}

	@Test func turningQueueingOffSteersNewFollowUpsWhileExistingQueueContinues(
	) async throws
	{
		try await withStartedQueue(["Queued A"])
		{
			harness in
			let fixture = harness.fixture
			fixture.inputs.setQueueingEnabled(false)
			#expect(!fixture.currentSnapshot.canQueue)
			fixture.inputs.updateDraft("Steer immediately")
			let steering = try #require(fixture.inputs.send())
			#expect(await steering.wait() == .finished)
			#expect(harness.service.steering.map(\.text) == ["Steer immediately"])
			#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["Queued A"])
			#expect(!fixture.currentSnapshot.queueingEnabled)
			try await fixture.store.drainPersistence()
			#expect(!fixture.draftStorage.queueingEnabled(
				for: harness.project,
				threadID: "chat-a"
			))
			harness.complete(
				"chat-a",
				status: "completed"
			)
			try await waitForQueueCount(
				0,
				conversation: .thread("chat-a"),
				store: fixture.store
			)
			#expect(harness.service.starts.map(\.text) == ["First", "Queued A"])
			try await fixture.store.drainPersistence()
		}
	}

	@Test func completingATurnContinuesOtherFollowUpsAndKeepsEditedInputAsDraft() async throws
	{
		try await withStartedQueue(["Original follow up", "Later follow up"])
		{
			harness in
			let fixture = harness.fixture
			let original = try #require(fixture.currentSnapshot.queuedMessages.first)
			fixture.inputs.beginEditingQueuedMessage(original)
			fixture.inputs.updateDraft("Unsaved revision")
			harness.complete(
				"chat-a",
				status: "completed"
			)
			try await waitForQueueCount(
				0,
				conversation: .thread("chat-a"),
				store: fixture.store
			)
			#expect(harness.service.starts.map(\.text) == ["First", "Later follow up"])
			#expect(fixture.currentSnapshot.draft == "Unsaved revision")
			#expect(!fixture.currentSnapshot.isEditingQueuedMessage)
			try await fixture.store.drainPersistence()
		}
	}

	@Test func relaunchRestoresOtherEntriesPausedAndKeepsEditedTextAsDraft() async throws
	{
		try await withStartedQueue(["A", "B"])
		{
			harness in
			let fixture = harness.fixture
			let original = fixture.currentSnapshot.queuedMessages
			fixture.inputs.beginEditingQueuedMessage(original[0])
			fixture.inputs.updateDraft("Revised A")
			try await fixture.store.drainPersistence()
			fixture.shutdown()
			let store = makeRestoredStore(harness)
			let restored = WorkspaceTestFixture(store: store)
			defer
			{
				restored.shutdown()
			}
			await restored.inputs.connect()
			let selection = try #require(restored.inputs.selectThread("chat-a"))
			#expect(await selection.wait() == .finished)
			#expect(!restored.currentSnapshot.isEditingQueuedMessage)
			#expect(restored.currentSnapshot.draft == "Revised A")
			#expect(restored.currentSnapshot.queuedMessages.map(\.text) == ["B"])
			#expect(restored.currentSnapshot.queuePaused)
			harness.complete(
				"chat-a",
				status: "completed"
			)
			let submission = try #require(restored.inputs.send())
			#expect(await submission.wait() == .finished)
			#expect(harness.service.starts.map(\.text) == ["First", "Revised A"])
			#expect(restored.currentSnapshot.queuedMessages.map(\.text) == ["B"])
			#expect(restored.currentSnapshot.queuePaused)
			try await store.drainPersistence()
		}
	}

	@Test func resumingChosenEntryContinuesOthersInOrderAndPreservesComposer() async throws
	{
		try await withStartedQueue(["A", "B", "C"])
		{
			harness in
			let fixture = harness.fixture
			let original = fixture.currentSnapshot.queuedMessages
			fixture.inputs.beginEditingQueuedMessage(original[1])
			fixture.inputs.updateDraft("Unsaved B")
			fixture.inputs.cancelQueuedMessageEdit()
			fixture.inputs.cancelQueuedMessageEdit()
			#expect(fixture.currentSnapshot.queuedMessages == original)
			#expect(fixture.currentSnapshot.draft.isEmpty)
			#expect(!fixture.currentSnapshot.isEditingQueuedMessage)
			let selected = try #require(fixture.currentSnapshot.queuedMessages.first
			{
				$0.text == "B"
			})
			harness.complete(
				"chat-a",
				status: "interrupted"
			)
			fixture.inputs.updateDraft("Unsent composer text")
			let operation = try #require(fixture.inputs.steerQueuedMessage(selected.id))
			#expect(await operation.wait() == .finished)
			#expect(harness.service.starts.map(\.text) == ["First", "B"])
			#expect(fixture.currentSnapshot.queuedMessages.map(\.text) == ["A", "C"])
			#expect(!fixture.currentSnapshot.queuePaused)
			#expect(fixture.currentSnapshot.draft == "Unsent composer text")
			for remaining in [1, 0]
			{
				try harness.completeLatest(
					"chat-a",
					status: "completed"
				)
				try await waitForQueueCount(
					remaining,
					conversation: .thread("chat-a"),
					store: fixture.store
				)
			}
			#expect(harness.service.starts.map(\.text) == ["First", "B", "A", "C"])
			#expect(fixture.currentSnapshot.draft == "Unsent composer text")
			try await fixture.store.drainPersistence()
		}
	}

	private func withStartedQueue(
		_ messages: [String],
		_ body: @MainActor (ConcurrentChatFixture) async throws -> Void
	) async throws
	{
		let harness = try ConcurrentChatFixture()
		defer
		{
			harness.cleanup()
		}
		await harness.fixture.inputs.connect()
		try await harness.start(
			"chat-a",
			text: "First"
		)
		for text in messages
		{
			harness.fixture.inputs.updateDraft(text)
			harness.fixture.inputs.send()
		}
		#expect(harness.fixture.currentSnapshot.queuedMessages.map(\.text) == messages)
		#expect(harness.service.starts.map(\.text) == ["First"])
		try await body(harness)
	}

	private func makeRestoredStore(_ harness: ConcurrentChatFixture) -> WorkspaceStateStore
	{
		let sessionID = UUID()
		return WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(reference: WorkspaceLifecycleOwnerReference(
				owner: .source(sessionID: sessionID),
				workspace: WorkspaceIdentity(
					sessionID: sessionID,
					canonicalCheckoutPath: harness.project.path
				)
			)),
			dependencies: harness.fixture.store.factoryDependencies
		)
	}

	private func waitForQueueCount(
		_ count: Int,
		conversation: ConversationKey,
		store: WorkspaceStateStore
	) async throws
	{
		if store.model.composer.drafts[conversation]?.queuedMessages.count == count
		{
			return
		}
		let signal = RuntimeSignal()
		let observation = store.observePublications
		{
			publication in
			if publication.model.composer.drafts[conversation]?.queuedMessages
				.count == count
			{
				signal.signal()
			}
		}
		defer
		{
			store.removePublicationObserver(observation)
		}
		await signal.wait()
	}
}
