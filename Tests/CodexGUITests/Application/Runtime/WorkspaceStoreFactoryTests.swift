import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspaceStoreFactoryTests
{
	private func fixture(
		publicationWait: @escaping @MainActor () async -> Void =
		{
		}
	) -> (WorkspaceStateStore, WorkspaceCodexService, LocalStorage, UserDefaults, String)
	{
		let suite = "WorkspaceFactory.\(UUID())"
		let defaults = UserDefaults(suiteName: suite)!
		let storage = LocalStorage(defaults: defaults)
		let directory = URL(fileURLWithPath: "/tmp")
		storage.saveSelectedThreadID(
			"factory-thread",
			for: directory
		)
		storage.saveDraft(
			"Persisted draft",
			for: directory,
			threadID: "factory-thread"
		)
		let service = WorkspaceCodexService(
			directory: directory,
			threadID: "factory-thread"
		)
		let session = UUID()
		let configuration = WorkspaceStoreConfiguration(reference: WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: session),
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: "/private/tmp"
			)
		))
		let contextDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("FactoryContext-\(UUID())")
		let store = WorkspaceStoreFactory.make(
			configuration: configuration,
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: storage,
				projectContextStore: ProjectContextStore(directory: contextDirectory),
				publicationWait: publicationWait
			)
		)
		return (store, service, storage, defaults, suite)
	}

	@Test func bootstrapUsesRealReducersAndRepeatedSelectionHydrationPreservesTheEdit() async throws
	{
		let (store, service, storage, defaults, suite) = fixture()
		defer
		{
			store.shutdown()
			defaults.removePersistentDomain(forName: suite)
		}
		#expect(store.currentSnapshot.selectedThreadID == "factory-thread")
		#expect(store.currentSnapshot.draft == "Persisted draft")
		await store.inputs.connect()
		#expect(service.connectionCount == 1)
		#expect(service.accountReadCount == 1)
		#expect(service.modelReadCount == 1)
		#expect(service.skillReadCount == 1)
		#expect(service.rateLimitReadCount == 1)
		#expect(service.readThreadCount == 1)
		#expect(store.currentSnapshot.canSend)
		store.inputs.updateDraft("Current visible edit")
		try await store.awaitAcceptedPersistence()
		for _ in 0 ..< 2
		{
			storage.saveDraft(
				"Obsolete stored draft",
				for: URL(fileURLWithPath: "/tmp"),
				threadID: "factory-thread"
			)
			let selection = try #require(store.inputs.selectThread("factory-thread"))
			#expect(await selection.wait() == .finished)
			#expect(store.currentSnapshot.draft == "Current visible edit")
			#expect(store.model.composer.drafts[.thread("factory-thread")]?.revision == 1)
		}
		#expect(service.connectionCount == 1)
	}

	@Test func publicationGateReleasesCanceledAndReplacementWaits() async
	{
		let gate = FactoryPublicationGate()
		let canceled = Task
		{
			await gate.wait()
		}
		await gate.waitForStart()
		canceled.cancel()
		let replacement = Task
		{
			await gate.wait()
		}
		await gate.waitForStart(count: 2)
		#expect(gate.pendingWaitCount == 2)
		gate.release()
		await canceled.value
		await replacement.value
		#expect(gate.pendingWaitCount == 0)
	}

	@Test func publicationBatchesOrderedDeltasAndRejectsTheCanceledSelectionBatch() async throws
	{
		for changeSelection in [false, true]
		{
			let gate = FactoryPublicationGate()
			let (store, service, _, defaults, suite) = fixture(publicationWait:
				{
					await gate.wait()
					gate.didReturn()
				})
			defer
			{
				store.shutdown()
				defaults.removePersistentDomain(forName: suite)
			}
			await store.inputs.connect()
			var snapshots: [ConversationSnapshot] = []
			let publication = WorkspacePublicationCoordinator(
				store: store,
				render:
				{
					snapshots.append($0)
				}
			)
			defer
			{
				publication.cancel()
			}
			#expect(snapshots.count == 1)
			service.emit(.turnStarted(
				threadId: service.thread.id,
				turn: service.turn
			))
			service.emit(.itemStarted(
				threadId: service.thread.id,
				turnId: service.turn.id,
				item: CodexItem(json: [
					"id": "answer",
					"type": "agentMessage",
					"text": "Initial"
				])!
			))
			let before = snapshots.count
			service.emit(.agentMessageDelta(
				threadId: service.thread.id,
				turnId: service.turn.id,
				itemId: "answer",
				text: " one"
			))
			#expect(store.currentSnapshot.entries.last?.body == "Initial one")
			service.emit(.agentMessageDelta(
				threadId: service.thread.id,
				turnId: service.turn.id,
				itemId: "answer",
				text: " two"
			))
			#expect(store.currentSnapshot.entries.last?.body == "Initial one two")
			await gate.waitForStart()
			#expect(snapshots.count == before)
			if changeSelection
			{
				store.inputs.newChat()
				if let selection = store.model.conversations.pendingSelectionPersistence
				{
					_ = await store.operation(for: selection)?.wait()
				}
				#expect(snapshots.last?.selectedThreadID == nil)
			}
			let beforeRelease = snapshots.count
			gate.release()
			await gate.waitForReturn()
			if changeSelection
			{
				#expect(snapshots.count == beforeRelease)
				#expect(snapshots.last?.entries.isEmpty == true)
			}
			else
			{
				#expect(snapshots.count == before + 1)
				#expect(snapshots.last?.entries.last?.body == "Initial one two")
			}
		}
	}
}

@MainActor
private final class FactoryPublicationGate
{
	private var startedCount = 0
	private var released = false
	private var returned = false
	private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
	var pendingWaitCount: Int
	{
		continuations.count
	}
	private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
	private var returnWaiters: [CheckedContinuation<Void, Never>] = []

	func wait() async
	{
		guard !released
		else
		{
			return
		}
		let id = UUID()
		await withCheckedContinuation
		{
			continuation in
			continuations[id] = continuation
			startedCount += 1
			let ready = startWaiters.filter
			{
				$0.count <= startedCount
			}
			startWaiters.removeAll
			{
				$0.count <= startedCount
			}
			for waiter in ready
			{
				waiter.continuation.resume()
			}
		}
	}
	func waitForStart(count: Int = 1) async
	{
		guard startedCount < count
		else
		{
			return
		}
		await withCheckedContinuation
		{
			startWaiters.append((count, $0))
		}
	}
	func release()
	{
		released = true
		let pending = Array(continuations.values)
		continuations.removeAll()
		for continuation in pending
		{
			continuation.resume()
		}
	}
	func didReturn()
	{
		returned = true
		for waiter in returnWaiters
		{
			waiter.resume()
		}
		returnWaiters.removeAll()
	}
	func waitForReturn() async
	{
		guard !returned
		else
		{
			return
		}
		await withCheckedContinuation
		{
			returnWaiters.append($0)
		}
	}
}
