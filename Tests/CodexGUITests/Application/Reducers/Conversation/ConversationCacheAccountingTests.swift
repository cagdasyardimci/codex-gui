import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationCacheAccountingTests
{
	private let threadID = "viewed"
	private let projectPath = "/tmp/cache-accounting"
	private let observedAt = Date(timeIntervalSince1970: 100)

	@Test func sourceDetailAndDisplayPayloadCanEvictOtherwiseSmallHistory() throws
	{
		var model = fixture()
		let items = (0 ..< 20).map
		{
			tool(
				"source-\($0)",
				largePayload: true
			)
		}
		let source = try #require(items.first?.sourceActivity)
		#expect(source.detail.utf8.count > 16_000)
		#expect(source.displayPayload.utf8.count == 16_384)
		#expect(items.allSatisfy
		{
			$0.text == nil && $0.output == nil
		})
		let turns = (0 ..< 56).map
		{
			turn(
				"source-turn-\($0)",
				items: items
			)
		}
		install(
			turns,
			in: "sources",
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)

		let retained = try #require(model.conversations.content[.thread("sources")])
		#expect(retained.loadedTurns.count < turns.count)
		#expect(!retained.loadedTurns.isEmpty)
		#expect(model.conversations.cacheAccounting.totalContentBytes
			<= ConversationCachePolicy.contentBytes)
		#expect(!model.conversations.cacheOverBudget)
		#expect(model.conversations.turnReferenceIndices["sources"]?.references.count == turns
			.count)
	}

	@Test func canonicalSourcesAndAttachmentReferencesAreNotChargedAgainInProjectedEntries()
	{
		var model = fixture()
		let history = turn(
			"history",
			items: [tool("source"), attachmentRequest()]
		)
		install(
			[history],
			model: &model
		)
		model.conversations.content[.thread(threadID)]?.entries = []
		ConversationReducer.enforceCacheLimits(model: &model)
		let canonicalBytes = model.conversations.cacheAccounting.totalContentBytes
		let projected = ConversationContentReducer.entries(for: [history])

		model.conversations.content[.thread(threadID)]?.entries = projected
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)

		let textBytes = projected.reduce(0)
		{
			$0 + 64 + $1.id.utf8.count + $1.title.utf8.count + $1.body.utf8.count
		}
		#expect(model.conversations.cacheAccounting.totalContentBytes == canonicalBytes + textBytes)
		#expect(model.conversations.cacheAccounting.content[threadID]?.additionalBytes == 0)
		#expect(model.conversations.cacheAccounting.content[threadID]?.additionalByTurn
			.isEmpty == true)
	}

	@Test func provisionalSourcesAndAttachmentsCountUntilTheirCanonicalItemsArrive() throws
	{
		var model = fixture()
		let future = turn(
			"live",
			items: [tool("source"), attachmentRequest()]
		)
		var provisional = ConversationContentReducer.entries(for: [future])
		let reference = try #require(provisional.last?.imageAttachments.first)
		// A reference can appear in both presentation collections without another payload copy.
		provisional[1].sourceReferences.append(reference)
		install(
			[],
			references: ["live"],
			model: &model
		)
		model.conversations.content[.thread(threadID)]?.entries = provisional
		ConversationReducer.enforceCacheLimits(model: &model)

		let source = try #require(future.items.first?.sourceActivity)
		let additional = ConversationCachePolicy.cost(source) + ConversationCachePolicy
			.cost(reference)
		#expect(model.conversations.cacheAccounting.content[threadID]?
			.additionalBytes == additional)
		#expect(model.conversations.cacheAccounting.content[threadID]?.additionalByTurn["live"]
			== additional)
		model.conversations.content[.thread(threadID)]?.loadedTurns = [future]
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)

		#expect(model.conversations.cacheAccounting.content[threadID]?.additionalBytes == 0)
		#expect(model.conversations.cacheAccounting.content[threadID]?.turns.byTurn["live"] != nil)
		#expect(model.conversations.content[.thread(threadID)]?.entries == provisional)
	}

	@Test func streamingAppendAndAuthoritativeShorteningUpdateUtf8CostsIncrementally() throws
	{
		var model = fixture()
		install(
			[],
			references: ["live"],
			model: &model
		)
		stream(
			"start",
			model: &model
		)
		let initial = model.conversations.cacheAccounting.totalContentBytes
		let before = try #require(model.conversations.content[.thread(threadID)])
		let additionalRevision = try #require(before.entryPayloadCosts?.additionalRevision)
		let fragment = "e\u{301}👩🏽‍💻"
		#expect(fragment.utf8.count > fragment.count)
		stream(
			fragment,
			model: &model
		)

		let appended = try #require(model.conversations.content[.thread(threadID)])
		#expect(model.conversations.cacheAccounting.totalContentBytes == initial + fragment.utf8
			.count)
		#expect(appended.entryPayloadRevision > before.entryPayloadRevision)
		#expect(appended.entryPayloadCosts?.additionalRevision == additionalRevision)
		#expect(appended.turnPayloadCosts?.totalBytes == before.turnPayloadCosts?.totalBytes)
		#expect(appended.entries.first?.body == "start" + fragment)

		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.backendObserved(
				.itemCompleted(
					threadId: threadID,
					turnId: "live",
					item: message(
						"reply",
						text: "x"
					)
				),
				observedAt: observedAt
			)
		)
		let shortened = try #require(model.conversations.content[.thread(threadID)])
		#expect(shortened.entries.first?.body == "x")
		#expect(shortened.entryPayloadCosts != nil)
		#expect(model.conversations.cacheAccounting.totalContentBytes == initial - "start".utf8
			.count + 1)
		let bytesBeforeNewEntry = model.conversations.cacheAccounting.totalContentBytes
		stream(
			"new response",
			itemID: "second",
			model: &model
		)
		let newEntry = try #require(model.conversations.content[.thread(threadID)]?.entries.last)
		#expect(model.conversations.cacheAccounting.totalContentBytes == bytesBeforeNewEntry
			+ 64 + newEntry.id.utf8.count + newEntry.title.utf8.count + newEntry.body.utf8.count)
		#expect(model.conversations.content[.thread(threadID)]?.entryPayloadCosts != nil)
	}

	@Test func scopedStreamingKeepsInactivePayloadCachesAndGapState() throws
	{
		var model = fixture()
		install(
			[],
			references: ["live"],
			model: &model
		)
		let inactiveTurns = [turn("a"), turn("c")]
		install(
			inactiveTurns,
			in: "inactive",
			references: ["a", "b", "c"],
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		let before = try #require(model.conversations.content[.thread("inactive")])
		let costs = try #require(model.conversations.cacheAccounting.content["inactive"])
		let index = try #require(model.conversations.turnReferenceIndices["inactive"])
		let revision = model.conversations.contentRevisions["inactive"]
		#expect(before.entries.contains
		{
			$0.id == "c:cache-gap"
		})

		stream(
			"first",
			model: &model
		)
		stream(
			" second",
			model: &model
		)

		let after = try #require(model.conversations.content[.thread("inactive")])
		let afterCosts = try #require(model.conversations.cacheAccounting.content["inactive"])
		#expect(after.entries == before.entries)
		#expect(after.loadedHistoryRevision == before.loadedHistoryRevision)
		#expect(after.entryPayloadRevision == before.entryPayloadRevision)
		#expect(after.entryPayloadCosts?.textBytes == before.entryPayloadCosts?.textBytes)
		#expect(after.turnPayloadCosts?.totalBytes == before.turnPayloadCosts?.totalBytes)
		#expect(afterCosts.totalBytes == costs.totalBytes)
		#expect(afterCosts.gapLoadedRevision == costs.gapLoadedRevision)
		#expect(afterCosts.gapReferenceRevision == costs.gapReferenceRevision)
		#expect(afterCosts.gapTurnIDs == costs.gapTurnIDs)
		#expect(model.conversations.turnReferenceIndices["inactive"]?.referencePositions
			== index.referencePositions)
		#expect(model.conversations.contentRevisions["inactive"] == revision)
	}

	@Test func oversizedProtectedResidentTurnsPreserveViewportLiveAndNavigationContent() throws
	{
		var model = fixture()
		let body = String(
			repeating: "x",
			count: 6 * 1024 * 1024
		)
		let protectedIDs: Set<String> = ["visible", "live", "destination"]
		let turns = [turn(
			"visible",
			text: body
		),
		turn(
			"live",
			text: body
		),
		turn(
			"destination",
			text: body
		),
		turn("evictable")]
		install(
			turns,
			references: turns.map(\.id) + ["missing"],
			model: &model
		)
		model.execution.activeThreadID = threadID
		model.execution.activeTurnID = "live"
		model.conversations.turnReferenceIndices[threadID]?.viewport = ConversationViewport(
			turnIDs: ["visible"],
			anchorTurnID: "visible"
		)
		model.conversations.turnReferenceIndices[threadID]?.navigationProtection = "destination"
		ConversationReducer.enforceCacheLimits(model: &model)

		let retained = try #require(model.conversations.content[.thread(threadID)])
		#expect(Set(retained.loadedTurns.map(\.id)) == protectedIDs)
		#expect(retained.entries.filter
		{
			!$0.id.hasSuffix(":cache-gap")
		}.count == 3)
		#expect(model.conversations.cacheOverBudget)
		#expect(model.conversations.turnReferenceIndices[threadID]?.references.count == 5)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.navigationProtection == "destination")
		var result = WorkspaceReduction()
		ConversationReducer.queueReadingWindow(
			threadID: threadID,
			model: &model,
			result: &result
		)
		#expect(result.effects.isEmpty)
	}

	@Test func oversizedProtectedProvisionalBodyPausesPrefetchWithoutDroppingLiveText() throws
	{
		var model = fixture()
		install(
			[turn("visible")],
			references: ["visible", "live", "missing"],
			model: &model
		)
		model.execution.activeThreadID = threadID
		model.execution.activeTurnID = "live"
		model.conversations.turnReferenceIndices[threadID]?.viewport = ConversationViewport(
			turnIDs: ["visible"],
			anchorTurnID: "visible"
		)
		let body = String(
			repeating: "x",
			count: ConversationCachePolicy.contentBytes
		)
		model.conversations.content[.thread(threadID)]?.appendEntry(ConversationEntry(
			id: "live:reply",
			kind: .agent,
			title: "Codex",
			body: body
		))
		ConversationReducer.enforceCacheLimits(model: &model)

		#expect(model.conversations.cacheOverBudget)
		let retained = try #require(model.conversations.content[.thread(threadID)])
		#expect(retained.loadedTurns.map(\.id) == ["visible"])
		#expect(retained.entries.last?.body == body)
		#expect(model.conversations.cacheAccounting.totalContentBytes
			> ConversationCachePolicy.contentBytes)
		var result = WorkspaceReduction()
		ConversationReducer.queueReadingWindow(
			threadID: threadID,
			model: &model,
			result: &result
		)
		#expect(result.effects.isEmpty)
		#expect(model.conversations.turnReferenceIndices[threadID]?.windowQueue.isEmpty == true)
	}

	@Test func removingReplacingAndDeletingContentReleasesItsRecordedBudget() throws
	{
		var model = fixture()
		install(
			[turn(
				"large",
				items: [tool("source")]
			), turn("small")],
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		let original = model.conversations.cacheAccounting.totalContentBytes
		model.conversations.content[.thread(threadID)]?.loadedTurns.removeFirst()
		model.conversations.content[.thread(threadID)]?.entries
			.removeAll
			{
				$0.id.hasPrefix("large:")
			}
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)
		#expect(model.conversations.cacheAccounting.totalContentBytes < original)
		#expect(model.conversations.cacheAccounting.content[threadID]?.turns.byTurn["large"] == nil)
		let afterRemoval = model.conversations.cacheAccounting.totalContentBytes

		let replacement = turn(
			"replacement",
			text: "x"
		)
		model.conversations.content[.thread(threadID)]?.loadedTurns = [replacement]
		model.conversations.content[.thread(threadID)]?.entries = ConversationContentReducer
			.entries(for: [replacement])
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)
		let costs = try #require(model.conversations.cacheAccounting.content[threadID])
		#expect(costs.turns.turnIDs == ["replacement"])
		#expect(costs.turns.byTurn["small"] == nil)
		#expect(costs.totalBytes != afterRemoval)
		#expect(costs.additionalBytes == 0)

		model.conversations.content[.thread(threadID)] = nil
		model.conversations.turnReferenceIndices[threadID] = nil
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)
		#expect(model.conversations.cacheAccounting.content[threadID] == nil)
		#expect(model.conversations.cacheAccounting.totalContentBytes == 0)
		#expect(!model.conversations.cacheOverBudget)
	}

	@Test(arguments: [false, true])
	func freshContentAndIndexWithMatchingRevisionsRefreshPayloadsAndGaps(replaceIndex: Bool) throws
	{
		var model = fixture()
		install(
			[turn("a"), turn("c")],
			references: ["a", "b", "c", "d"],
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		let oldContent = try #require(model.conversations.content[.thread(threadID)])
		let oldIndex = try #require(model.conversations.turnReferenceIndices[threadID])
		let original = model.conversations.cacheAccounting.totalContentBytes
		let replacements = [turn(
			"b",
			text: String(
				repeating: "b",
				count: 4000
			)
		), turn("d")]
		let fresh = ConversationContentModel(
			loadedTurns: replacements,
			entries: ConversationContentReducer.entries(for: replacements)
		)
		#expect(fresh.loadedHistoryRevision == oldContent.loadedHistoryRevision)
		model.conversations.content[.thread(threadID)] = fresh
		if replaceIndex
		{
			var index = TurnReferenceIndex()
			index.references = ["d", "c", "b", "a"].map(reference)
			#expect(index.referenceRevision == oldIndex.referenceRevision)
			model.conversations.turnReferenceIndices[threadID] = index
		}
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)

		let refreshed = try #require(model.conversations.content[.thread(threadID)])
		let expectedTurns = replaceIndex ? ["d", "b"] : ["b", "d"]
		#expect(refreshed.loadedTurns.map(\.id) == expectedTurns)
		#expect(refreshed.entries.filter
		{
			$0.id.hasSuffix(":cache-gap")
		}.map(\.id)
		== [expectedTurns[1] + ":cache-gap"])
		#expect(model.conversations.cacheAccounting.content[threadID]?.turns
			.turnIDs == expectedTurns)
		#expect(model.conversations.cacheAccounting.content[threadID]?.turns.byTurn["a"] == nil)
		#expect(model.conversations.cacheAccounting.totalContentBytes > original)
	}

	@Test func rebuildingOnlyCanonicalEntriesRestoresSparseHistoryGapMarkers() throws
	{
		var model = fixture()
		let turns = [turn("a"), turn("c")]
		install(
			turns,
			references: ["a", "b", "c"],
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)
		let initial = try #require(model.conversations.content[.thread(threadID)])
		let originalBytes = model.conversations.cacheAccounting.totalContentBytes
		#expect(initial.entries.contains
		{
			$0.id == "c:cache-gap"
		})
		model.conversations.content[.thread(threadID)]?.entries = ConversationContentReducer
			.entries(for: turns)
		ConversationReducer.enforceCacheLimits(
			model: &model,
			updating: [threadID]
		)

		let restored = try #require(model.conversations.content[.thread(threadID)])
		#expect(restored.loadedHistoryRevision == initial.loadedHistoryRevision)
		#expect(restored.entries == initial.entries)
		#expect(model.conversations.cacheAccounting.totalContentBytes == originalBytes)
	}

	@Test func overlapOnlyEarlierPageKeepsMissingTurnGapVisible() throws
	{
		var model = fixture()
		let turns = [turn("a"), turn("c")]
		install(
			turns,
			references: ["a", "b", "c"],
			model: &model
		)
		model.conversations.content[.thread(threadID)]?.nextTurnsCursor = "older"
		ConversationReducer.enforceCacheLimits(model: &model)
		let entries = try #require(model.conversations.content[.thread(threadID)]?.entries)
		#expect(entries.contains
		{
			$0.id == "c:cache-gap"
		})
		let operation = HistoryLoadOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: threadID
			),
			pageScope: HistoryPageScope(
				projectPath: projectPath,
				generation: model.connection.generation,
				cursor: "older"
			),
			commandRevision: 0
		)
		reduce(
			.conversations(.earlierTurnsRequested(operation)),
			model: &model
		)
		reduce(
			.conversations(.earlierTurnsReceived(
				operation,
				.succeeded(HistoryPage(
					turns: [turns[0]],
					nextCursor: "more"
				))
			)),
			model: &model
		)

		let accepted = try #require(model.conversations.content[.thread(threadID)])
		#expect(accepted.loadedTurns.map(\.id) == ["a", "c"])
		#expect(accepted.entries == entries)
		#expect(accepted.nextTurnsCursor == "more")
		#expect(model.conversations.historyLoads[threadID] == nil)
		#expect(model.conversations.cacheAccounting.content[threadID]?.gapTurnIDs == ["a", "c"])
	}

	@Test func duplicateReferenceIDsUseTheirFirstPositionWithoutLosingResidentRows() throws
	{
		var model = fixture()
		install(
			[turn("c"), turn("a")],
			references: ["a", "a", "b", "c"],
			model: &model
		)
		ConversationReducer.enforceCacheLimits(model: &model)

		let index = try #require(model.conversations.turnReferenceIndices[threadID])
		#expect(index.referencePositions?["a"] == 0)
		#expect(index.referencePositions?["c"] == 3)
		#expect(index.references.map(\.id) == ["a", "a", "b", "c"])
		let content = try #require(model.conversations.content[.thread(threadID)])
		#expect(content.loadedTurns.map(\.id) == ["a", "c"])
		#expect(content.entries.filter
		{
			!$0.id.hasSuffix(":cache-gap")
		}.map(\.id)
		== ["a:reply", "c:reply"])
		#expect(content.entries.filter
		{
			$0.id.hasSuffix(":cache-gap")
		}.count == 1)
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: projectPath
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread(threadID)
		return model
	}

	private func install(
		_ turns: [CodexTurn],
		in target: String? = nil,
		references: [String]? = nil,
		model: inout WorkspaceModel
	)
	{
		let target = target ?? threadID
		model.conversations.content[.thread(target)] = ConversationContentModel(
			loadedTurns: turns,
			entries: ConversationContentReducer.entries(for: turns)
		)
		var index = TurnReferenceIndex()
		index.references = (references ?? turns.map(\.id)).map(reference)
		model.conversations.turnReferenceIndices[target] = index
	}

	private func reference(_ id: String) -> ConversationTurnReference
	{
		ConversationTurnReference(
			id: id,
			status: "completed"
		)
	}

	private func turn(
		_ id: String,
		text: String = "Reply"
	) -> CodexTurn
	{
		turn(
			id,
			items: [message(
				"reply",
				text: text
			)]
		)
	}

	private func turn(
		_ id: String,
		items: [CodexItem]
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: items,
			error: nil
		)
	}

	private func message(
		_ id: String,
		text: String
	) -> CodexItem
	{
		CodexItem(json: ["id": id, "type": "agentMessage", "text": text])!
	}

	private func tool(
		_ id: String,
		largePayload: Bool = false
	) -> CodexItem
	{
		let argument = String(
			repeating: "a",
			count: largePayload ? 4096 : 512
		)
		return CodexItem(json: [
			"id": id,
			"type": "mcpToolCall",
			"server": "test",
			"tool": "read",
			"status": "completed",
			"arguments": ["first": argument,
							"second": argument,
							"third": argument,
							"fourth": argument,
							"fifth": argument],
			"result": String(
				repeating: "z",
				count: largePayload ? 16_384 : 2048
			)
		])!
	}

	private func attachmentRequest() -> CodexItem
	{
		CodexItem(json: [
			"id": "request",
			"type": "userMessage",
			"content": [["type": "image",
							"url": "data:image/png;base64,"
							+ String(
								repeating: "a",
								count: 2048
							)]]
		])!
	}

	private func stream(
		_ text: String,
		itemID: String = "reply",
		model: inout WorkspaceModel
	)
	{
		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.backendObserved(
				.agentMessageDelta(
					threadId: threadID,
					turnId: "live",
					itemId: itemID,
					text: text
				),
				observedAt: observedAt
			)
		)
	}

	private func reduce(
		_ action: WorkspaceAction,
		model: inout WorkspaceModel
	)
	{
		let result = WorkspaceFeatureComposition.reduce(
			&model,
			action
		)
		for event in result.domainEvents
		{
			_ = ConversationReviewComposition.reduceDomainEvent(
				&model,
				event
			)
		}
	}
}
