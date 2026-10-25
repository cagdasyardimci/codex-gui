import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationCacheAccountingTests
{
	private let threadID = "viewed"
	private let projectPath = "/tmp/cache-accounting"
	private let observedAt = Date(timeIntervalSince1970: 100)

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
