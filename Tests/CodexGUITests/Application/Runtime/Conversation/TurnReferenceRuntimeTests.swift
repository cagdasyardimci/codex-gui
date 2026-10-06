import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnReferenceRuntimeTests
{
	@Test func railReferencesCoverAllTurnsWhileOnlyTheLatestTwentyFiveHaveContent() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		let snapshot = fixture.state.currentSnapshot
		#expect(snapshot.turnReferences.map(\.id) == (0 ..< 66).map
		{
			"turn-\($0)"
		})
		#expect(snapshot.entries.count == 50)
		#expect(snapshot.entries.first?.id == "turn-41:request")
		#expect(fixture.service.turnContentReads.isEmpty)
		#expect(fixture.service.earlierReadCursors.isEmpty)
	}

	@Test func selectingAnOlderReferenceLoadsOnlyThatTurn() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		let reads = fixture.service.readThreadCount
		fixture.state.inputs.jumpToNavigationTarget(ConversationJumpTarget(
			threadID: fixture.service.thread.id,
			turnID: "turn-4",
			itemID: nil,
			filePath: nil,
			kind: .userRequest,
			title: "Earlier turn"
		))
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
		})
		#expect(fixture.service.turnContentReads.map(\.turnID) == ["turn-4"])
		#expect(fixture.service.readThreadCount == reads)
		#expect(fixture.service.earlierReadCursors.isEmpty)
		#expect(fixture.state.currentSnapshot.entries.filter
		{
			!$0.id.hasSuffix(":cache-gap")
		}
		.count == 52)
		#expect(fixture.state.currentSnapshot.entries.first?.id == "turn-4:request")
		#expect(!fixture.state.currentSnapshot.entries.contains
		{
			$0.id == "turn-5:request"
		})
	}

	@Test func hoveringCachesOnlyThePreviewAndClickingReusesItsContent() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		let entries = fixture.state.currentSnapshot.entries
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.turnPreviews.first?.turnID == "turn-4"
		})
		#expect(fixture.state.currentSnapshot.entries == entries)
		#expect(fixture.state.currentSnapshot.pendingJumpItemID == nil)
		#expect(fixture.service.turnContentReads.map(\.turnID) == ["turn-4"])
		fixture.state.inputs.jumpToNavigationTarget(ConversationJumpTarget(
			threadID: fixture.service.thread.id,
			turnID: "turn-4",
			itemID: nil,
			filePath: nil,
			kind: .userRequest,
			title: "Earlier turn"
		))
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
		})
		#expect(fixture.service.turnContentReads.map(\.turnID) == ["turn-4"])
		#expect(fixture.state.currentSnapshot.entries.filter
		{
			!$0.id.hasSuffix(":cache-gap")
		}
		.count == 52)
	}

	@Test func referencePaginationLeavesTranscriptContentAndItsCursorUntouched() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture(pagedReferences: true)
		defer
		{
			fixture.close()
		}
		let entries = fixture.state.currentSnapshot.entries
		let cursor = fixture.state.store.model.conversations
			.content[.thread(fixture.service.thread.id)]?.nextTurnsCursor
		fixture.state.inputs.loadEarlierTurnReferences()
		fixture.state.inputs.loadEarlierTurnReferences()
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.turnReferences.count == 66
		})
		#expect(fixture.state.currentSnapshot.entries == entries)
		#expect(fixture.service.turnReferenceReads.compactMap(\.cursor) == ["older-references"])
		#expect(fixture.service.turnContentReads.isEmpty)
		#expect(fixture.service.earlierReadCursors.isEmpty)
		#expect(fixture.state.store.model.conversations.content[.thread(fixture.service.thread.id)]?
			.nextTurnsCursor == cursor)
		#expect(!fixture.state.currentSnapshot.canLoadEarlierTurnReferences)
	}

	@Test func previewFetchPromotesToNavigationWithoutAnotherBackendRead() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			fixture.service.pendingTurnContentRead != nil
		})
		fixture.state.inputs.jumpToNavigationTarget(ConversationJumpTarget(
			threadID: fixture.service.thread.id,
			turnID: "turn-4",
			itemID: nil,
			filePath: nil,
			kind: .userRequest,
			title: "Earlier turn"
		))
		#expect(fixture.service.turnContentReads.count == 1)
		let turn = try #require(fixture.service.referencedTurnContents["turn-4"])
		fixture.service.pendingTurnContentRead?.resume(returning: turn)
		fixture.service.pendingTurnContentRead = nil
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
		})
		#expect(fixture.service.turnContentReads.count == 1)
	}

	@Test func aNewHoverDoesNotCancelThePreviewServingTheForegroundJump() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		let threadID = fixture.service.thread.id
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			fixture.service.pendingTurnContentRead != nil
		})
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
		try #require(await waitForTurnReferenceCondition
		{
			fixture.service.turnContentReads.count == 2
				&& fixture.service.pendingTurnContentRead != nil
		})
		#expect(fixture.state.store.operation(for: promotion.producer.context)?.completion == nil)
		let firstTurn = try #require(fixture.service.referencedTurnContents["turn-4"])
		first?.resume(returning: firstTurn)
		first = nil
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
		})
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
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.turnPreviews.contains
			{
				$0.turnID == "turn-5"
			}
		})
		#expect(fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request")
	}

	@Test func aPreviewServingTheReadingWindowFinishesAndContinuesItsQueue() async throws
	{
		let fixture = try await makeTurnReferenceTestFixture()
		defer
		{
			fixture.close()
		}
		let threadID = fixture.service.thread.id
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			fixture.service.pendingTurnContentRead != nil
		})
		fixture.state.inputs.updateConversationViewport(ConversationViewport(
			turnIDs: ["turn-4"],
			anchorTurnID: "turn-4"
		))
		#expect(fixture.state.store.model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewPromotion?.consumer.isWindow == true)
		#expect(fixture.service.turnContentReads.count == 1)
		fixture.service.suspendTurnContentRead = false
		let turn = try #require(fixture.service.referencedTurnContents["turn-4"])
		fixture.service.pendingTurnContentRead?.resume(returning: turn)
		fixture.service.pendingTurnContentRead = nil
		try #require(await waitForTurnReferenceCondition
		{
			let index = fixture.state.store.model.conversations.turnReferenceIndices[threadID]
			return index?.pendingWindowRead == nil && index?.windowQueue.isEmpty == true
		})
		#expect(fixture.state.store.model.conversations.content[.thread(threadID)]?
			.loadedTurns.contains
			{
				$0.id == "turn-4"
			} == true)
		#expect(fixture.service.turnContentReads.filter
		{
			$0.turnID == "turn-4"
		}.count == 1)
		#expect(fixture.service.turnContentReads.count > 1)
		#expect(fixture.state.store.model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewPromotion == nil)
	}

	@Test func injectedPreviewPreparationRunsAwayFromTheMainActor() async throws
	{
		let fixture =
			try await makeTurnReferenceTestFixture(previewPreparer: ProbePreviewPreparer())
		defer
		{
			fixture.close()
		}
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.turnPreviews.first?.title == "Prepared outside reducer"
		})
	}

	@Test func supersedingAHoverCancelsItsDetachedPreviewPreparation() async throws
	{
		let preparer = SuspendedPreviewPreparer()
		let fixture = try await makeTurnReferenceTestFixture(previewPreparer: preparer)
		defer
		{
			fixture.close()
		}
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitForTurnReferenceCondition
		{
			preparer.hasStarted
		})
		fixture.state.inputs.loadTurnPreview("turn-5")
		try #require(await waitForTurnReferenceCondition
		{
			preparer.wasCancelled
				&& fixture.state.currentSnapshot.turnPreviews.first?.turnID == "turn-5"
		})
		#expect(!fixture.state.currentSnapshot.turnPreviews.contains
		{
			$0.turnID == "turn-4"
		})
	}

	@Test func scrollingFromTheEndToTheBeginningKeepsContentBoundedAndReloadsEvictedTurns(
	) async throws
	{
		let fixture = try await makeTurnReferenceTestFixture(totalTurns: 132)
		defer
		{
			fixture.close()
		}
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
			try #require(await waitForTurnReferenceCondition
			{
				fixture.state.store.model.conversations.turnReferenceIndices[threadID]?
					.pendingWindowRead == nil
			})
			#expect(fixture.state.store.model.conversations.content[.thread(threadID)]?.loadedTurns
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
		try #require(await waitForTurnReferenceCondition
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-131:request"
		})
		#expect(fixture.service.turnContentReads.contains
		{
			$0.turnID == "turn-131"
		})
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
			lock.withLock
			{
				started = true
			}
			while !Task.isCancelled
			{
				Thread.sleep(forTimeInterval: 0.001)
			}
			lock.withLock
			{
				cancelled = true
			}
			throw CancellationError()
		}
	}

}
