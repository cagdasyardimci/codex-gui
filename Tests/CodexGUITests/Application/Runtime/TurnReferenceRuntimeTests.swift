import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnReferenceRuntimeTests
{
	@Test func railReferencesCoverAllTurnsWhileOnlyTheLatestTwentyFiveHaveContent() async throws
	{
		let fixture = try await fixture()
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
		let fixture = try await fixture()
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
		try #require(await waitUntil
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
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let entries = fixture.state.currentSnapshot.entries
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
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
		try #require(await waitUntil
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
		let fixture = try await fixture(pagedReferences: true)
		defer
		{
			fixture.close()
		}
		let entries = fixture.state.currentSnapshot.entries
		let cursor = fixture.state.store.model.conversations
			.content[.thread(fixture.service.thread.id)]?.nextTurnsCursor
		fixture.state.inputs.loadEarlierTurnReferences()
		fixture.state.inputs.loadEarlierTurnReferences()
		try #require(await waitUntil
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

	@Test(arguments: [false, true])
	func aLateReferencePageCannotReplaceANewerRequest(reconnected: Bool) async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let state = fixture.state.store
		let threadID = fixture.service.thread.id
		let old = TurnReferenceReadOperation(
			context: state.operationContext(threadID: threadID),
			cursor: "older"
		)
		var model = state.model
		model.conversations.turnReferenceIndices[threadID]?.nextCursor = "older"
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.turnReferencesRequested(old))
		)
		var newerContext = old.context
		newerContext = OperationContext(
			workspace: newerContext.workspace,
			generation: newerContext.generation + (reconnected ? 1 : 0),
			requestID: UUID(),
			threadID: threadID
		)
		model.connection.generation = newerContext.generation
		model.conversations.turnReferenceIndices[threadID]?
			.pendingRead = TurnReferenceReadOperation(
				context: newerContext,
				cursor: nil
			)
		let before = model.conversations.turnReferenceIndices[threadID]?.references
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.turnReferencesReceived(
				old,
				.succeeded(TurnReferencePage(
					references: [ConversationTurnReference(
						id: "obsolete",
						status: "completed"
					)],
					nextCursor: nil
				))
			))
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.references == before)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead?
			.context == newerContext)
	}

	@Test func aLateTurnReadCannotOverwriteNewCommandEvidence() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let state = fixture.state.store
		let threadID = fixture.service.thread.id
		var model = state.model
		let reference = try #require(model.conversations.turnReferenceIndices[threadID]?.references
			.first
			{
				$0.id == "turn-4"
			})
		let operation = ConversationTurnReadOperation(
			context: state.operationContext(threadID: threadID),
			reference: reference,
			commandRevision: 0
		)
		model.conversations.pendingTurnReads[threadID] = operation
		model.execution.commandEventRevisions[threadID] = 1
		let entries = model.conversations.content[.thread(threadID)]?.entries
		let turn = try #require(fixture.service.referencedTurnContents[reference.id])
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.turnContentsReceived(
				operation,
				.succeeded(turn)
			))
		)
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.pendingTurnReads[threadID] == nil)
	}

	@Test func previewReadsDoNotReplaceAnUnfinishedNavigationRead() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let store = fixture.state.store
		let threadID = fixture.service.thread.id
		var model = store.model
		let references = try #require(model.conversations.turnReferenceIndices[threadID]?
			.references)
		let navigation = ConversationTurnReadOperation(
			context: store.operationContext(threadID: threadID),
			reference: references[4],
			commandRevision: model.execution.commandEventRevisions[threadID, default: 0]
		)
		let preview = ConversationTurnReadOperation(
			context: store.operationContext(threadID: threadID),
			reference: references[5],
			commandRevision: navigation.commandRevision,
			isPreview: true
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.turnContentsRequested(navigation))
		)
		let effects = ConversationReducer.reduce(
			&model,
			.conversations(.turnContentsRequested(preview))
		)
		#expect(model.conversations.pendingTurnReads[threadID] == navigation)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == preview)
		#expect(effects.effects.count == 1)
		let entries = model.conversations.content[.thread(threadID)]?.entries
		let turn = try #require(fixture.service.referencedTurnContents["turn-5"])
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.turnContentsReceived(
				preview,
				.succeeded(turn)
			))
		)
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.pendingTurnReads[threadID] == navigation)
	}

	@Test func metadataRequestsRequireAValidatedConversationInTheCheckout() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let state = fixture.state.store
		let threadID = fixture.service.thread.id
		var model = state.model
		model.conversations.content[.thread(threadID)] = ConversationContentModel()
		model.conversations.turnReferenceIndices[threadID] = TurnReferenceIndex()
		model.conversations.threads = [ThreadSummary(json: [
			"id": threadID,
			"cwd": "/tmp/another-checkout"
		])!]
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.turnReferencesRequested(TurnReferenceReadOperation(
				context: state.operationContext(threadID: threadID),
				cursor: nil
			)))
		)
		#expect(result.effects.isEmpty)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil)
	}

	@Test func hoverContentIsBoundedAndExpiresWhileCompactPreviewsSurvive() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let threadID = fixture.service.thread.id
		for index in 0 ..< 205
		{
			let turn = cacheTurn(index)
			ConversationReducer.cachePreview(
				turn,
				preview: try ConversationMarkdownPreviewPreparer().prepare(turn),
				threadID: threadID,
				model: &model
			)
			ConversationReducer.enforceCacheLimits(model: &model)
		}
		let cached = try #require(model.conversations.turnReferenceIndices[threadID])
		#expect(cached.previewTurns.count == 3)
		#expect(cached.previews.count == 200)
		#expect(cached.previews["cache-0"] == nil)
		#expect(cached.previews["cache-204"] != nil)
		ConversationReducer.enforceCacheLimits(
			model: &model,
			now: Date().addingTimeInterval(16)
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previewTurns.isEmpty == true)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews.count == 200)
	}

	@Test func contentEvictionProtectsTheVisibleTurnAndMarksMissingRanges() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let threadID = fixture.service.thread.id
		let turns = (0 ..< 80).map
		{
			cacheTurn($0)
		}
		model.conversations.content[.thread(threadID)]?.loadedTurns = turns
		model.conversations.content[.thread(threadID)]?.entries = ConversationContentReducer
			.entries(for: turns)
		model.conversations.turnReferenceIndices[threadID]?.references = turns.map
		{
			ConversationTurnReference(
				id: $0.id,
				status: "completed"
			)
		}
		model.conversations.turnReferenceIndices[threadID]?.viewport = ConversationViewport(
			turnIDs: ["cache-0"],
			anchorTurnID: "cache-0"
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		let content = try #require(model.conversations.content[.thread(threadID)])
		#expect(content.loadedTurns.count == 75)
		#expect(content.loadedTurns.first?.id == "cache-0")
		#expect(!content.loadedTurns.contains
		{
			$0.id == "cache-1"
		})
		#expect(!content.entries.contains
		{
			$0.id == "cache-1:request"
		})
		#expect(content.entries.contains
		{
			$0.id.hasSuffix(":cache-gap")
		})
		#expect(model.conversations.turnReferenceIndices[threadID]?.references.count == 80)
	}

	@Test func previewFetchPromotesToNavigationWithoutAnotherBackendRead() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
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
		try #require(await waitUntil
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-4:request"
		})
		#expect(fixture.service.turnContentReads.count == 1)
	}

	@Test func aNewHoverDoesNotCancelThePreviewServingTheForegroundJump() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let threadID = fixture.service.thread.id
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
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
		try #require(await waitUntil
		{
			fixture.service.turnContentReads.count == 2
				&& fixture.service.pendingTurnContentRead != nil
		})
		#expect(fixture.state.store.operation(for: promotion.producer.context)?.completion == nil)
		let firstTurn = try #require(fixture.service.referencedTurnContents["turn-4"])
		first?.resume(returning: firstTurn)
		first = nil
		try #require(await waitUntil
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
		try #require(await waitUntil
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
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		let threadID = fixture.service.thread.id
		fixture.service.suspendTurnContentRead = true
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
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
		try #require(await waitUntil
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
		let fixture = try await fixture(previewPreparer: ProbePreviewPreparer())
		defer
		{
			fixture.close()
		}
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
		{
			fixture.state.currentSnapshot.turnPreviews.first?.title == "Prepared outside reducer"
		})
	}

	@Test func supersedingAHoverCancelsItsDetachedPreviewPreparation() async throws
	{
		let preparer = SuspendedPreviewPreparer()
		let fixture = try await fixture(previewPreparer: preparer)
		defer
		{
			fixture.close()
		}
		fixture.state.inputs.loadTurnPreview("turn-4")
		try #require(await waitUntil
		{
			preparer.hasStarted
		})
		fixture.state.inputs.loadTurnPreview("turn-5")
		try #require(await waitUntil
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
		let fixture = try await fixture(totalTurns: 132)
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
			try #require(await waitUntil
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
		try #require(await waitUntil
		{
			fixture.state.currentSnapshot.pendingJumpItemID == "turn-131:request"
		})
		#expect(fixture.service.turnContentReads.contains
		{
			$0.turnID == "turn-131"
		})
	}

	@Test func oversizedVisibleContentPausesPrefetchAndEvictsUnprotectedContent() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let threadID = fixture.service.thread.id
		let turns = [
			cacheTurn(
				0,
				text: String(
					repeating: "x",
					count: 16 * 1024 * 1024
				)
			),
			cacheTurn(1)
		]
		model.conversations.content[.thread(threadID)]?.loadedTurns = turns
		model.conversations.content[.thread(threadID)]?.entries = ConversationContentReducer
			.entries(for: turns)
		model.conversations.turnReferenceIndices[threadID]?.references = turns.map
		{
			ConversationTurnReference(
				id: $0.id,
				status: "completed"
			)
		}
		model.conversations.turnReferenceIndices[threadID]?.viewport = ConversationViewport(
			turnIDs: ["cache-0"],
			anchorTurnID: "cache-0"
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		#expect(model.conversations.cacheOverBudget)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) == ["cache-0"])
		var result = WorkspaceReduction()
		ConversationReducer.queueReadingWindow(
			threadID: threadID,
			model: &model,
			result: &result
		)
		#expect(result.effects.isEmpty)
	}

	@Test func contentBudgetIsSharedAcrossChatsAndInactiveContentIsEvicted() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let oversized = cacheTurn(
			0,
			text: String(
				repeating: "x",
				count: 16 * 1024 * 1024
			)
		)
		model.conversations.content[.thread("inactive")] = ConversationContentModel(
			loadedTurns: [oversized],
			entries: ConversationContentReducer.entries(for: [oversized])
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		#expect(model.conversations.content[.thread("inactive")]?.loadedTurns.isEmpty == true)
		#expect(model.conversations.content[.thread("inactive")]?.entries.isEmpty == true)
		#expect(!model.conversations.cacheOverBudget)
		#expect(fixture.state.currentSnapshot.entries.count == 50)
	}

	@Test func revisitingACompactPreviewProtectsItFromLeastRecentlyUsedEviction() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let threadID = fixture.service.thread.id
		for index in 0 ..< 200
		{
			ConversationReducer.cachePreview(
				cacheTurn(index),
				preview: try ConversationMarkdownPreviewPreparer().prepare(cacheTurn(index)),
				threadID: threadID,
				model: &model
			)
		}
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.previewAccessed(
				fixture.state.store.operationContext(threadID: threadID),
				"cache-0"
			))
		)
		ConversationReducer.cachePreview(
			cacheTurn(200),
			preview: try ConversationMarkdownPreviewPreparer().prepare(cacheTurn(200)),
			threadID: threadID,
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["cache-0"] != nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["cache-1"] == nil)
	}

	@Test func partialAndEmptyPreviewsNeverBecomeCompleteCachedTranscriptTurns() async throws
	{
		let fixture = try await fixture()
		defer
		{
			fixture.close()
		}
		var model = fixture.state.store.model
		let threadID = fixture.service.thread.id
		let original = cacheTurn(0)
		let partial = CodexTurn(
			id: original.id,
			status: original.status,
			items: original.items,
			error: nil,
			itemsAreComplete: false
		)
		ConversationReducer.cachePreview(
			partial,
			preview: try ConversationMarkdownPreviewPreparer().prepare(partial),
			threadID: threadID,
			model: &model
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews[original.id] != nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.previewTurns[original.id] == nil)
		let empty = CodexTurn(
			id: "empty",
			status: "completed",
			items: [],
			error: nil
		)
		ConversationReducer.cachePreview(
			empty,
			preview: try ConversationMarkdownPreviewPreparer().prepare(empty),
			threadID: threadID,
			model: &model
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["empty"]?.reply
			== "No text preview is available.")
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

	private func cacheTurn(
		_ index: Int,
		text: String = "Reply"
	) -> CodexTurn
	{
		CodexTurn(json: ["id": "cache-\(index)", "status": "completed", "items": [
			[
				"id": "request",
				"type": "userMessage",
				"content": [["type": "text", "text": "Request"]]
			],
			["id": "reply", "type": "agentMessage", "text": text]
		]])!
	}

	@MainActor
	private struct Fixture
	{
		let state: WorkspaceTestFixture
		let service: MockCodexService
		let project: URL

		func close()
		{
			state.shutdown()
			service.pendingTurnContentRead?.resume(throwing: CancellationError())
			service.pendingTurnContentRead = nil
			try? FileManager.default.removeItem(at: project)
		}
	}

	private func fixture(
		pagedReferences: Bool = false,
		totalTurns: Int = 66,
		previewPreparer: any ConversationPreviewPreparing = ConversationMarkdownPreviewPreparer()
	) async throws -> Fixture
	{
		let project = FileManager.default.temporaryDirectory.appendingPathComponent(
			"TurnReferenceTests-\(UUID())",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		let service = MockCodexService()
		service.configureCheckout(project)
		let turns = (0 ..< totalTurns).map
		{
			index in
			CodexTurn(json: ["id": "turn-\(index)", "status": "completed", "items": [
				[
					"id": "request",
					"type": "userMessage",
					"content": [["type": "text", "text": "Request \(index)"]]
				],
				["id": "reply", "type": "agentMessage", "text": "Reply \(index)"],
			]])!
		}
		let references = turns.map
		{
			ConversationTurnReference(
				id: $0.id,
				status: $0.status
			)
		}
		service.savedTurns = Array(turns.suffix(25))
		service.readNextCursor = "older-content"
		service.referencedTurnContents = Dictionary(uniqueKeysWithValues: turns.map
		{
			($0.id, $0)
		})
		service.turnReferencePages[""] = TurnReferencePage(
			references: pagedReferences ? Array(references.suffix(50)) : references,
			nextCursor: pagedReferences ? "older-references" : nil
		)
		service.turnReferencePages["older-references"] = TurnReferencePage(
			references: Array(references.prefix(16)),
			nextCursor: nil
		)
		let defaults = try #require(UserDefaults(suiteName: "TurnReferenceTests.\(UUID())"))
		let state = WorkspaceTestFixture(store: WorkspaceStoreFactory.makeSource(
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: LocalStorage(defaults: defaults),
				previewPreparer: previewPreparer
			)
		))
		await state.inputs.connect()
		state.inputs.openProject(project)
		try #require(await waitUntil
		{
			state.currentSnapshot.canManageThreads
		})
		state.inputs.selectThread(service.thread.id)
		try #require(await waitUntil
		{
			state.currentSnapshot.entries.count == 50 && state.currentSnapshot.turnReferences
				.count == (pagedReferences ? 50 : totalTurns)
		})
		return Fixture(
			state: state,
			service: service,
			project: project
		)
	}

	private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 200
		{
			if predicate()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return predicate()
	}
}
