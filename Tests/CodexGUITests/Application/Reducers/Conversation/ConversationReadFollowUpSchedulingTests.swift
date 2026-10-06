import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationReadFollowUpSchedulingTests
{
	@Test func referenceSchedulingDefersRequestIdentityUntilTheInputBoundary()
	{
		var model = fixture()
		model.conversations.turnReferenceIndices[threadID]?.hasLoadedPage = false
		var first = WorkspaceReduction()
		var repeated = WorkspaceReduction()
		ConversationReducer.ensureTurnReferences(
			model: &model,
			result: &first
		)
		ConversationReducer.ensureTurnReferences(
			model: &model,
			result: &repeated
		)
		let expected = ConversationReadFollowUp.references(
			scope(model),
			cursor: nil
		)

		#expect(captures(in: first) == [expected])
		#expect(captures(in: repeated) == [expected])
		#expect(first.effects.count == 1)
		#expect(repeated.effects.count == 1)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead == nil)
		#expect(model.conversations.pendingTurnReads.isEmpty)
	}

	@Test func repeatedViewportSchedulingEmitsTheSameCapturedValuesWithoutPendingUUIDs()
	{
		var model = fixture()
		model.conversations.turnReferenceIndices[threadID]?.nextCursor = "older"
		let action = WorkspaceAction.conversations(.viewportChanged(
			context(
				model,
				requestID: 9
			),
			ConversationViewport(
				turnIDs: ["older-a"],
				anchorTurnID: "older-a"
			),
			observedAt: observedAt
		))
		let first = ConversationReducer.reduce(
			&model,
			action
		)
		let repeated = ConversationReducer.reduce(
			&model,
			action
		)
		let expected: [ConversationReadFollowUp] = [
			.references(
				scope(model),
				cursor: "older"
			),
			.window(
				scope(model),
				reference: reference("older-a"),
				commandRevision: 0
			)
		]

		#expect(captures(in: first) == expected)
		#expect(captures(in: repeated) == expected)
		#expect(first.effects.count == expected.count)
		#expect(repeated.effects.count == expected.count)
		#expect(model.conversations.turnReferenceIndices[threadID]?.windowQueue.map(\.id) == [
			"older-a",
			"older-b"
		])
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead == nil)
		#expect(model.conversations.pendingTurnReads.isEmpty)
	}

	@Test func replayedReferenceCompletionSchedulesEqualValuesWithoutCreatingNewOperations()
	{
		var seed = fixture()
		let operation = TurnReferenceReadOperation(
			context: context(
				seed,
				requestID: 10
			),
			cursor: "older"
		)
		seed.conversations.turnReferenceIndices[threadID]?.references = [reference("resident")]
		seed.conversations.turnReferenceIndices[threadID]?.pendingRead = operation
		seed.conversations.turnReferenceIndices[threadID]?.viewport = ConversationViewport(
			turnIDs: ["older-a"],
			anchorTurnID: "older-a"
		)
		let action = WorkspaceAction.conversations(.turnReferencesReceived(
			operation,
			.succeeded(TurnReferencePage(
				references: [reference("older-a"), reference("older-b")],
				nextCursor: "oldest"
			))
		))
		var firstModel = seed
		var replayedModel = seed
		let first = ConversationReducer.reduce(
			&firstModel,
			action
		)
		let replayed = ConversationReducer.reduce(
			&replayedModel,
			action
		)
		let expected: [ConversationReadFollowUp] = [
			.references(
				scope(seed),
				cursor: "oldest"
			),
			.window(
				scope(seed),
				reference: reference("older-a"),
				commandRevision: 0
			)
		]

		#expect(captures(in: first) == expected)
		#expect(captures(in: replayed) == expected)
		#expect(first.effects.count == expected.count)
		#expect(replayed.effects.count == expected.count)
		for model in [firstModel, replayedModel]
		{
			#expect(model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil)
			#expect(model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead == nil)
			#expect(model.conversations.pendingTurnReads.isEmpty)
		}
	}

	private let threadID = "thread"
	private let observedAt = Date(timeIntervalSince1970: 1_000)

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: uuid(240),
			canonicalCheckoutPath: "/tmp/turn-read-promotion"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread(threadID)
		let resident = turn("resident")
		model.conversations.content[.thread(threadID)] = ConversationContentModel(
			loadedTurns: [resident],
			hasLoadedHistory: true,
			entries: ConversationContentReducer.entries(for: [resident])
		)
		var index = TurnReferenceIndex()
		index.references = [reference("older-a"), reference("older-b"), reference("resident")]
		index.hasLoadedPage = true
		model.conversations.turnReferenceIndices[threadID] = index
		return model
	}

	private func uuid(_ value: UInt8) -> UUID
	{
		UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
	}

	private func context(
		_ model: WorkspaceModel,
		requestID: UInt8
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: uuid(requestID),
			threadID: threadID
		)
	}

	private func scope(_ model: WorkspaceModel) -> ConversationReadScope
	{
		ConversationReadScope(
			workspace: model.identity,
			generation: model.connection.generation,
			threadID: threadID
		)
	}

	private func reference(_ id: String) -> ConversationTurnReference
	{
		ConversationTurnReference(
			id: id,
			status: "completed"
		)
	}

	private func turn(_ id: String) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": "answer",
				"type": "agentMessage",
				"text": "Reply for \(id)"
			])!],
			error: nil
		)
	}

	private func captures(in result: WorkspaceReduction) -> [ConversationReadFollowUp]
	{
		result.effects.compactMap
		{
			if case .captureConversationRead(let value) = $0
			{
				return value
			}
			return nil
		}
	}
}
