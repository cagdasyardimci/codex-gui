import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnReadPromotionTests
{
	@Test(arguments: [false, true])
	func producerFailureFinishesItsForegroundOrWindowConsumer(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		let failure = OperationFailure(
			message: "Transport closed",
			outcomeIsUncertain: false
		)
		let result = receive(
			promotion.producer,
			observation: .failed(failure),
			model: &model
		)

		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) == ["resident"])
		#expect(reads(in: result).isEmpty)
		if isWindow
		{
			#expect(model.conversations.turnReferenceIndices[threadID]?.windowError == failure
				.message)
			#expect(model.conversations.turnReferenceIndices[threadID]?.windowQueue.isEmpty == true)
			#expect(terminals(in: result).isEmpty)
		}
		else
		{
			#expect(terminals(in: result) == [Terminal(
				operation: promotion.consumer,
				outcome: .failed(failure)
			)])
		}
	}

	@Test(arguments: [false, true])
	func newCommandEvidenceRetiresBothKindsOfPromotedConsumer(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		model.execution.commandEventRevisions[threadID] = 1
		let entries = model.conversations.content[.thread(threadID)]?.entries
		let result = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)

		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["older-a"] == nil)
		#expect(reads(in: result).isEmpty)
		if isWindow
		{
			#expect(model.conversations.turnReferenceIndices[threadID]?.windowQueue.isEmpty == true)
		}
		#expect(terminals(in: result) == [Terminal(
			operation: promotion.consumer,
			outcome: .succeeded(false)
		)])
	}

	@Test(arguments: [false, true])
	func partialPreviewRequestsExactlyOneFullReadForItsCapturedConsumer(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		let result = receive(
			promotion.producer,
			observation: .succeeded(turn(
				"older-a",
				itemsAreComplete: false
			)),
			preview: preview("older-a"),
			model: &model
		)

		#expect(reads(in: result) == [promotion.consumer])
		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == promotion.consumer)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previewTurns["older-a"] == nil)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) == ["resident"])
		#expect(terminals(in: result).isEmpty)

		let finished = receive(
			promotion.consumer,
			observation: .succeeded(turn("older-a")),
			model: &model
		)
		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.map(\.id) == [
			"older-a",
			"resident"
		])
		#expect(reads(in: finished).isEmpty)
		#expect(terminals(in: finished) == (isWindow ? [] : [Terminal(
			operation: promotion.consumer,
			outcome: .succeeded(true)
		)]))
	}

	@Test(arguments: [false, true])
	func newerHoverKeepsThePromotedProducerAndItsConsumerAlive(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		let newerPreview = operation(
			model,
			turnID: "older-b",
			requestID: 3,
			isPreview: true
		)
		let newerRequest = request(
			newerPreview,
			model: &model
		)
		#expect(reads(in: newerRequest) == [newerPreview])
		#expect(cancellations(in: newerRequest).isEmpty)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewRead == newerPreview)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewPromotion == promotion)

		let finished = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)
		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewRead == newerPreview)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.map(\.id) == [
			"older-a",
			"resident"
		])
		#expect(terminals(in: finished) == (isWindow ? [] : [Terminal(
			operation: promotion.consumer,
			outcome: .succeeded(true)
		)]))

		_ = receive(
			newerPreview,
			observation: .succeeded(turn("older-b")),
			preview: preview("older-b"),
			model: &model
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["older-b"] != nil)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.map(\.id) == [
			"older-a",
			"resident"
		])
	}

	@Test(arguments: [false, true])
	func newerForegroundReadRetiresThePreviousPromotion(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		let replacement = operation(
			model,
			turnID: "older-b",
			requestID: 3
		)
		let result = request(
			replacement,
			model: &model
		)

		#expect(model.conversations.pendingTurnReads[threadID] == replacement)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(reads(in: result) == [replacement])
		#expect(cancellations(in: result) == [promotion.producer.context])
		if !isWindow
		{
			#expect(terminals(in: result) == [Terminal(
				operation: promotion.consumer,
				outcome: .failed(OperationFailure(
					message: "Another turn read replaced this request.",
					outcomeIsUncertain: false
				))
			)])
		}

		let entries = model.conversations.content[.thread(threadID)]?.entries
		let late = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)
		#expect(late.effects.isEmpty)
		#expect(late.domainEvents.isEmpty)
		#expect(model.conversations.pendingTurnReads[threadID] == replacement)
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["older-a"] == nil)
	}

	@Test func replacementWindowConsumerPreservesItsRemainingNeighborhoodQueue()
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: true
		)
		let remainingReference = reference("older-c")
		model.conversations.turnReferenceIndices[threadID]?.references = [
			reference("older-a"),
			reference("older-b"),
			remainingReference,
			reference("resident")
		]
		model.conversations.turnReferenceIndices[threadID]?.windowQueue = [
			reference("older-b"),
			remainingReference
		]
		let replacement = operation(
			model,
			turnID: "older-b",
			requestID: 3,
			isWindow: true
		)
		let result = request(
			replacement,
			model: &model
		)

		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingWindowRead == replacement)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.windowQueue == [remainingReference])
		#expect(reads(in: result) == [replacement])
		#expect(cancellations(in: result) == [promotion.producer.context])
		#expect(terminals(in: result).isEmpty)

		let finished = receive(
			replacement,
			observation: .succeeded(turn("older-b")),
			model: &model
		)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.windowQueue == [remainingReference])
		#expect(captures(in: finished) == [
			.window(
				scope(model),
				reference: remainingReference,
				commandRevision: 0
			)
		])
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.map(\.id) == [
			"older-b",
			"resident"
		])
	}

	@Test(arguments: [false, true])
	func changingSelectionRetiresThePromotionBeforeItsLateCompletion(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		model.conversations.selectedConversation = .thread("other")
		var result = WorkspaceReduction()
		ConversationReducer.ensureTurnReferences(
			model: &model,
			result: &result
		)

		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(cancellations(in: result) == [promotion.producer.context])
		if !isWindow
		{
			#expect(terminals(in: result) == [Terminal(
				operation: promotion.consumer,
				outcome: .failed(OperationFailure(
					message: "The displayed conversation changed before this turn was loaded.",
					outcomeIsUncertain: false
				))
			)])
		}

		let entries = model.conversations.content[.thread(threadID)]?.entries
		let late = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)
		#expect(late.effects.isEmpty)
		#expect(late.domainEvents.isEmpty)
		#expect(model.conversations.selectedConversation == .thread("other"))
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["older-a"] == nil)
	}

	@Test(
		arguments: [false, true],
		[false, true]
	)
	func obsoleteWorkspaceOrGenerationCannotFinishAPromotedConsumer(
		isWindow: Bool,
		changesWorkspace: Bool
	)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		if changesWorkspace
		{
			model.identity = WorkspaceIdentity(
				sessionID: uuid(241),
				canonicalCheckoutPath: model.identity.canonicalCheckoutPath
			)
		}
		else
		{
			model.connection.generation += 1
		}
		let entries = model.conversations.content[.thread(threadID)]?.entries
		let result = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)

		#expect(result.effects.isEmpty)
		#expect(result.domainEvents.isEmpty)
		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == promotion.consumer)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewPromotion == promotion)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == promotion
			.producer)
		#expect(model.conversations.content[.thread(threadID)]?.entries == entries)
		#expect(model.conversations.turnReferenceIndices[threadID]?.previews["older-a"] == nil)
	}

	@Test(
		arguments: [false, true],
		[false, true]
	)
	func retainedObsoletePreviewCannotAcquireAFreshConsumer(
		isWindow: Bool,
		changesWorkspace: Bool
	)
	{
		var model = fixture()
		let producer = operation(
			model,
			turnID: "older-a",
			requestID: 1,
			isPreview: true
		)
		_ = request(
			producer,
			model: &model
		)
		if changesWorkspace
		{
			model.identity = WorkspaceIdentity(
				sessionID: uuid(241),
				canonicalCheckoutPath: model.identity.canonicalCheckoutPath
			)
		}
		else
		{
			model.connection.generation += 1
		}
		if isWindow
		{
			model.conversations.turnReferenceIndices[threadID]?.windowQueue = [reference("older-a")]
		}
		let consumer = operation(
			model,
			turnID: "older-a",
			requestID: 2,
			isWindow: isWindow
		)
		let result = request(
			consumer,
			model: &model
		)
		let retained = ConversationTurnReadPromotion(
			producer: producer,
			consumer: consumer
		)

		#expect(reads(in: result) == [consumer])
		#expect(pendingConsumer(
			in: model,
			promotion: retained
		) == consumer)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(!result.effects.contains
		{
			if case .promoteTurnContents = $0
			{
				return true
			}
			return false
		})

		let late = receive(
			producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)
		#expect(late.effects.isEmpty)
		#expect(late.domainEvents.isEmpty)
		#expect(pendingConsumer(
			in: model,
			promotion: retained
		) == consumer)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) == ["resident"])
	}

	@Test(arguments: [false, true])
	func completePromotionStoresOneCanonicalTurnAndNoDuplicateHoverBody(isWindow: Bool)
	{
		var model = fixture()
		let promotion = promote(
			model: &model,
			isWindow: isWindow
		)
		let result = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)

		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == nil)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.map(\.id) == [
			"older-a",
			"resident"
		])
		#expect(model.conversations.turnReferenceIndices[threadID]?.previewTurns["older-a"] == nil)
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.previewCachedAt["older-a"] == nil)
		#expect(reads(in: result).isEmpty)
		#expect(terminals(in: result) == (isWindow ? [] : [Terminal(
			operation: promotion.consumer,
			outcome: .succeeded(true)
		)]))
		#expect(result.domainEvents.filter
		{
			if case .conversationContentChanged = $0
			{
				return true
			}
			return false
		}.count == 1)

		let duplicate = receive(
			promotion.producer,
			observation: .succeeded(turn("older-a")),
			preview: preview("older-a"),
			model: &model
		)
		#expect(duplicate.effects.isEmpty)
		#expect(duplicate.domainEvents.isEmpty)
		#expect(model.conversations.content[.thread(threadID)]?.loadedTurns.filter
		{
			$0.id == "older-a"
		}.count == 1)
	}

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

	private func operation(
		_ model: WorkspaceModel,
		turnID: String,
		requestID: UInt8,
		isPreview: Bool = false,
		isWindow: Bool = false
	) -> ConversationTurnReadOperation
	{
		ConversationTurnReadOperation(
			context: context(
				model,
				requestID: requestID
			),
			reference: reference(turnID),
			commandRevision: model.execution.commandEventRevisions[threadID, default: 0],
			isPreview: isPreview,
			isWindow: isWindow
		)
	}

	private func turn(
		_ id: String,
		itemsAreComplete: Bool = true
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": "answer",
				"type": "agentMessage",
				"text": "Reply for \(id)"
			])!],
			error: nil,
			itemsAreComplete: itemsAreComplete
		)
	}

	private func preview(_ id: String) -> ConversationTurnPreview
	{
		ConversationTurnPreview(
			turnID: id,
			entryID: "\(id):answer",
			title: id,
			reply: "Reply for \(id)"
		)
	}

	private func promote(
		model: inout WorkspaceModel,
		isWindow: Bool
	) -> ConversationTurnReadPromotion
	{
		let producer = operation(
			model,
			turnID: "older-a",
			requestID: 1,
			isPreview: true
		)
		let consumer = operation(
			model,
			turnID: "older-a",
			requestID: 2,
			isWindow: isWindow
		)
		if isWindow
		{
			model.conversations.turnReferenceIndices[threadID]?.windowQueue = [reference("older-a")]
		}
		let previewRequest = request(
			producer,
			model: &model
		)
		let consumerRequest = request(
			consumer,
			model: &model
		)
		let promotion = ConversationTurnReadPromotion(
			producer: producer,
			consumer: consumer
		)
		#expect(reads(in: previewRequest) == [producer])
		#expect(reads(in: consumerRequest).isEmpty)
		#expect(consumerRequest.effects.compactMap
		{
			if case .promoteTurnContents(let value) = $0
			{
				return value
			}
			return nil
		} == [promotion])
		#expect(model.conversations.turnReferenceIndices[threadID]?
			.pendingPreviewPromotion == promotion)
		#expect(pendingConsumer(
			in: model,
			promotion: promotion
		) == consumer)
		return promotion
	}

	private func request(
		_ operation: ConversationTurnReadOperation,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		ConversationReducer.requestTurnContents(
			operation,
			model: &model,
			result: &result
		)
		return result
	}

	private func receive(
		_ operation: ConversationTurnReadOperation,
		observation: OperationResult<CodexTurn>,
		preview: ConversationTurnPreview? = nil,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		ConversationReducer.receiveTurnContents(
			operation,
			observation: observation,
			observedAt: observedAt,
			preview: preview,
			model: &model,
			result: &result
		)
		return result
	}

	private func pendingConsumer(
		in model: WorkspaceModel,
		promotion: ConversationTurnReadPromotion
	) -> ConversationTurnReadOperation?
	{
		promotion.consumer.isWindow
			? model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead
			: model.conversations.pendingTurnReads[threadID]
	}

	private func reads(in result: WorkspaceReduction) -> [ConversationTurnReadOperation]
	{
		result.effects.compactMap
		{
			if case .readTurnContents(let operation) = $0
			{
				return operation
			}
			return nil
		}
	}

	private func cancellations(in result: WorkspaceReduction) -> [OperationContext]
	{
		result.effects.compactMap
		{
			if case .cancel(let context) = $0
			{
				return context
			}
			return nil
		}
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

	private enum TerminalOutcome: Equatable
	{
		case succeeded(Bool)
		case failed(OperationFailure)
	}

	private struct Terminal: Equatable
	{
		let operation: ConversationTurnReadOperation
		let outcome: TerminalOutcome
	}

	private func terminals(in result: WorkspaceReduction) -> [Terminal]
	{
		result.domainEvents.compactMap
		{
			guard case .conversationHistoryFinished(
				.turn(let operation),
				let observation
			) = $0
			else
			{
				return nil
			}
			switch observation
			{
			case .succeeded(let accepted):
				return Terminal(
					operation: operation,
					outcome: .succeeded(accepted)
				)
			case .failed(let failure):
				return Terminal(
					operation: operation,
					outcome: .failed(failure)
				)
			}
		}
	}
}
