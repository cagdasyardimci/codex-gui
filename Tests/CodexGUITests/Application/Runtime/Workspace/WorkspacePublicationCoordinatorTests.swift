import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspacePublicationCoordinatorTests
{
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
			let (store, service, _, defaults, suite) = WorkspaceStoreFactoryFixture
				.make(publicationWait:
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
