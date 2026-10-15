import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnReferenceReducerTests
{
	@Test(arguments: [false, true])
	func aLateReferencePageCannotReplaceANewerRequest(reconnected: Bool) async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
	}

	@Test func aLateTurnReadCannotOverwriteNewCommandEvidence() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
			let state = fixture.state.store
			let threadID = fixture.service.thread.id
			var model = state.model
			let reference = try #require(model.conversations.turnReferenceIndices[threadID]?
				.references
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
	}

	@Test func previewReadsDoNotReplaceAnUnfinishedNavigationRead() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
			#expect(model.conversations.turnReferenceIndices[threadID]?
				.pendingPreviewRead == preview)
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
	}

	@Test func metadataRequestsRequireAValidatedConversationInTheCheckout() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
	}

	@Test func hoverContentIsBoundedAndExpiresWhileCompactPreviewsSurvive() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
			#expect(model.conversations.turnReferenceIndices[threadID]?.previewTurns
				.isEmpty == true)
			#expect(model.conversations.turnReferenceIndices[threadID]?.previews.count == 200)
		}
	}

	@Test func contentEvictionProtectsTheVisibleTurnAndMarksMissingRanges() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
	}
	@Test func oversizedVisibleContentPausesPrefetchAndEvictsUnprotectedContent() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
	}

	@Test func contentBudgetIsSharedAcrossChatsAndInactiveContentIsEvicted() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
			var model = fixture.state.store.model
			let selectedConversation = model.conversations.selectedConversation
			let selectedContent = try #require(model.conversations.content[selectedConversation])
			#expect(selectedContent.entries.count == 50)
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
			let retained = try #require(model.conversations.content[selectedConversation])
			#expect(model.conversations.selectedConversation == selectedConversation)
			#expect(retained.entries == selectedContent.entries)
			#expect(retained.loadedTurns.map(\.id) == selectedContent.loadedTurns.map(\.id))
		}
	}

	@Test func revisitingACompactPreviewProtectsItFromLeastRecentlyUsedEviction() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
	}

	@Test func partialAndEmptyPreviewsNeverBecomeCompleteCachedTranscriptTurns() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
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
			#expect(model.conversations.turnReferenceIndices[threadID]?
				.previews[original.id] != nil)
			#expect(model.conversations.turnReferenceIndices[threadID]?
				.previewTurns[original.id] == nil)
			let empty = CodexTurn(
				id: "empty",
				status: "completed",
				items: [],
				error: nil,
				itemsAreComplete: false
			)
			ConversationReducer.cachePreview(
				empty,
				preview: try ConversationMarkdownPreviewPreparer().prepare(empty),
				threadID: threadID,
				model: &model
			)
			#expect(model.conversations.turnReferenceIndices[threadID]?.previews["empty"]?.reply
				== "No text preview is available.")
			#expect(model.conversations.turnReferenceIndices[threadID]?
				.previewTurns["empty"] == nil)
			#expect(model.conversations.turnReferenceIndices[threadID]?
				.previewCachedAt["empty"] == nil)
			let reference = ConversationTurnReference(
				id: empty.id,
				status: empty.status
			)
			model.conversations.turnReferenceIndices[threadID]?.references.insert(
				reference,
				at: 0
			)
			ConversationReducer.enforceCacheLimits(model: &model)
			let navigation = ConversationTurnReadOperation(
				context: fixture.state.store.operationContext(threadID: threadID),
				reference: reference,
				commandRevision: model.execution.commandEventRevisions[threadID, default: 0]
			)
			let entries = model.conversations.content[.thread(threadID)]?.entries
			let result = ConversationReducer.reduce(
				&model,
				.conversations(.turnContentsRequested(navigation))
			)
			#expect(model.conversations.pendingTurnReads[threadID] == navigation)
			#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
			#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.contains
			{
				$0.id == "empty"
			} == false)
			#expect(result.effects.count == 1)
			#expect(result.effects.contains
			{
				if case .readTurnContents(let operation) = $0
				{
					return operation == navigation
				}
				return false
			})
		}
	}

	@Test func completeEmptyPreviewSuppliesForegroundReadWithoutAnotherRequest() async throws
	{
		try await withTurnReferenceTestFixture()
		{
			fixture in
			var model = fixture.state.store.model
			let threadID = fixture.service.thread.id
			let empty = CodexTurn(
				id: "empty",
				status: "completed",
				items: [],
				error: nil,
				itemsAreComplete: true
			)
			ConversationReducer.cachePreview(
				empty,
				preview: try ConversationMarkdownPreviewPreparer().prepare(empty),
				threadID: threadID,
				model: &model
			)
			#expect(model.conversations.turnReferenceIndices[threadID]?.previews["empty"]?.reply
				== "No text preview is available.")
			#expect(model.conversations.turnReferenceIndices[threadID]?.previewTurns["empty"]?
				.itemsAreComplete == true)
			let reference = ConversationTurnReference(
				id: empty.id,
				status: empty.status
			)
			model.conversations.turnReferenceIndices[threadID]?.references.insert(
				reference,
				at: 0
			)
			let navigation = ConversationTurnReadOperation(
				context: fixture.state.store.operationContext(threadID: threadID),
				reference: reference,
				commandRevision: model.execution.commandEventRevisions[threadID, default: 0]
			)
			let result = ConversationReducer.reduce(
				&model,
				.conversations(.turnContentsRequested(navigation))
			)
			#expect(model.conversations.pendingTurnReads[threadID] == nil)
			#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.first?
				.id == "empty")
			#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.first?.items.isEmpty
				== true)
			#expect(result.effects.isEmpty)
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

}
