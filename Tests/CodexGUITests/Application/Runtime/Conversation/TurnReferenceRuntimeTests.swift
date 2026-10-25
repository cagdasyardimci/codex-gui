import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1))) @MainActor
struct TurnReferenceRuntimeTests
{

	@Test func aNewHoverDoesNotCancelThePreviewServingTheForegroundJump() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
			let threadID = fixture.service.thread.id
			fixture.service.suspendTurnContentRead = true
			fixture.state.inputs.loadTurnPreview("turn-4")
			try #require(await fixture.service.awaitReadiness(matching:
				{
					fixture.service.pendingTurnContentRead != nil
				}))
			var first = fixture.service.pendingTurnContentRead
			fixture.service.pendingTurnContentRead = nil
			defer
			{
				first?.resume(throwing: CancellationError())
				fixture.service.pendingTurnContentRead?.resume(throwing: CancellationError())
				fixture.service.pendingTurnContentRead = nil
			}
			fixture.state.inputs.jumpToNavigationTarget(ConversationJumpTarget(
				threadID: threadID,
				turnID: "turn-4",
				itemID: nil,
				filePath: nil,
				kind: .userRequest,
				title: "Earlier turn"
			))
			let promotion = try #require(fixture.state.store.model.conversations
				.turnReferenceIndices[threadID]?.pendingPreviewPromotion)
			fixture.state.inputs.loadTurnPreview("turn-5")
			try #require(await fixture.service.awaitReadiness(matching:
				{
					fixture.service.turnContentReads.count == 2
						&& fixture.service.pendingTurnContentRead != nil
				}))
			#expect(fixture.state.store.operation(for: promotion.producer.context)?
				.completion == nil)
			let firstTurn = try #require(fixture.service.referencedTurnContents["turn-4"])
			first?.resume(returning: firstTurn)
			first = nil
			try #require(await fixture.awaitSnapshot(matching:
				{
					fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
				}))
			#expect(fixture.state.store.model.conversations.pendingTurnReads[threadID] == nil)
			let index = try #require(fixture.state.store.model.conversations
				.turnReferenceIndices[threadID])
			#expect(index.pendingPreviewPromotion == nil)
			#expect(index.pendingPreviewRead?.reference.id == "turn-5")
			#expect(index.previewTurns["turn-4"] == nil)
			#expect(fixture.service.turnContentReads.map(\.turnID) == ["turn-4", "turn-5"])
			let nextTurn = try #require(fixture.service.referencedTurnContents["turn-5"])
			fixture.service.pendingTurnContentRead?.resume(returning: nextTurn)
			fixture.service.pendingTurnContentRead = nil
			try #require(await fixture.awaitSnapshot(matching:
				{
					fixture.state.currentSnapshot.turnPreviews.contains
					{
						$0.turnID == "turn-5"
					}
				}))
			#expect(fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request")
		}
	}

	@Test func scrollingFromTheEndToTheBeginningKeepsContentBoundedAndReloadsEvictedTurns(
	) async throws
	{
		try await withTurnReferenceTestFixture(totalTurns: 132)
		{
			fixture in
			let threadID = fixture.service.thread.id
			for position in stride(
				from: 131,
				through: 1,
				by: -10
			)
			{
				let turnID = "turn-\(position)"
				fixture.state.inputs.updateConversationViewport(ConversationViewport(
					turnIDs: [turnID],
					anchorTurnID: turnID,
					firstTurnID: turnID,
					lastTurnID: turnID
				))
				// A completed read clears its slot before the next queued read is captured.
				// Await the whole queue before advancing to another viewport.
				try #require(await fixture.awaitSnapshot(matching:
					{
						let index = fixture.state.store.model.conversations
							.turnReferenceIndices[threadID]
						return index?.pendingWindowRead == nil && index?.windowQueue.isEmpty == true
					}))
				#expect(fixture.state.store.model.conversations.content[.thread(threadID)]?
					.loadedTurns
					.count ?? 0 <= 75)
			}
			#expect(fixture.state.store.model.conversations.content[.thread(threadID)]?
				.loadedTurns.contains
				{
					$0.id == "turn-0"
				} == true)
			#expect(fixture.state.store.model.conversations.content[.thread(threadID)]?
				.loadedTurns.contains
				{
					$0.id == "turn-131"
				} == false)
			fixture.state.inputs.jumpToNavigationTarget(ConversationJumpTarget(
				threadID: threadID,
				turnID: "turn-131",
				itemID: nil,
				filePath: nil,
				kind: .userRequest,
				title: "Latest"
			))
			try #require(await fixture.awaitSnapshot(matching:
				{
					fixture.state.currentSnapshot.pendingJumpItemID == "turn-131:request"
				}))
			#expect(fixture.service.turnContentReads.contains
			{
				$0.turnID == "turn-131"
			})
		}
	}

	private struct ProbePreviewPreparer: ConversationPreviewPreparing
	{
		func prepare(_ turn: CodexTurn) throws -> ConversationTurnPreview
		{
			#expect(!Thread.isMainThread)
			return ConversationTurnPreview(
				turnID: turn.id,
				entryID: turn.id + ":request",
				title: "Prepared outside reducer",
				reply: "Prepared reply"
			)
		}
	}

	private final class SuspendedPreviewPreparer: ConversationPreviewPreparing, @unchecked Sendable
	{
		private let lock = NSLock()
		private var started = false
		private var cancelled = false
		private var startWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]
		private var cancellationWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]

		func awaitStarted() async -> Bool
		{
			await awaitCheckpoint(cancelled: false)
			return hasStarted
		}

		func awaitCancelled() async -> Bool
		{
			await awaitCheckpoint(cancelled: true)
			return wasCancelled
		}

		private func awaitCheckpoint(cancelled awaitCancellation: Bool) async
		{
			let id = UUID()
			let stream = AsyncStream<Void>
			{
				continuation in
				continuation.onTermination =
				{
					[weak self] _ in
					guard let self
					else
					{
						return
					}
					self.lock.withLock
					{
						self.startWaiters.removeValue(forKey: id)
						self.cancellationWaiters.removeValue(forKey: id)
					}
				}
				let alreadyReached = lock.withLock
				{
					let reached = awaitCancellation ? cancelled : started
					if !reached
					{
						if awaitCancellation
						{
							cancellationWaiters[id] = continuation
						}
						else
						{
							startWaiters[id] = continuation
						}
					}
					return reached
				}
				if alreadyReached
				{
					continuation.yield(())
					continuation.finish()
				}
			}
			for await _ in stream
			{
				break
			}
		}

		private func signalCheckpoint(cancelled isCancellation: Bool)
		{
			let waiters = lock.withLock
			{
				if isCancellation
				{
					cancelled = true
					let ready = Array(cancellationWaiters.values)
					cancellationWaiters.removeAll()
					return ready
				}
				started = true
				let ready = Array(startWaiters.values)
				startWaiters.removeAll()
				return ready
			}
			// Finish outside the lock: stream termination retires its waiter under the same lock.
			for waiter in waiters
			{
				waiter.yield(())
				waiter.finish()
			}
		}

		var hasStarted: Bool
		{
			lock.withLock
			{
				started
			}
		}

		var wasCancelled: Bool
		{
			lock.withLock
			{
				cancelled
			}
		}

		func prepare(_ turn: CodexTurn) throws -> ConversationTurnPreview
		{
			guard turn.id == "turn-4"
			else
			{
				return try ConversationTextPreviewPreparer().prepare(turn)
			}
			signalCheckpoint(cancelled: false)
			while !Task.isCancelled
			{
				Thread.sleep(forTimeInterval: 0.001)
			}
			signalCheckpoint(cancelled: true)
			throw CancellationError()
		}
	}

}
