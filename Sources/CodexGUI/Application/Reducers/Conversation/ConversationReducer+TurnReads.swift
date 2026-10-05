import Foundation

extension ConversationReducer
{
	static func requestTurnContents(
		_ operation: ConversationTurnReadOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		), let threadID = operation.context.threadID, model.connection.isConnected,
		model.conversations.selectedConversation == .thread(threadID),
		model.conversations.boundThreadID == nil || model.conversations.boundThreadID == threadID,
		let index = model.conversations.turnReferenceIndices[threadID],
		index.references.contains(operation.reference),
		operation.commandRevision == model.execution.commandEventRevisions[threadID, default: 0]
		else
		{
			return
		}
		if operation.isWindow,
			model.conversations.pendingTurnReads[threadID] != nil
			|| model.conversations.cacheOverBudget
			|| !index.windowQueue.contains(operation.reference)
		{
			return
		}
		let producer = [index.pendingPreviewRead, index.pendingPreviewPromotion?.producer]
			.compactMap
			{
				$0
			}
			.first
			{
				$0.reference == operation.reference
					&& $0.commandRevision == operation.commandRevision
					&& $0.context.workspace == operation.context.workspace
					&& $0.context.generation == operation.context.generation
			}
		if !operation.isPreview, let previous = index.pendingPreviewPromotion,
			previous.consumer != operation
		{
			model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = nil
			if previous.producer != producer, index.pendingPreviewRead == previous.producer
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
			}
			receiveTurnContents(
				previous.consumer,
				observation: .failed(OperationFailure(
					message: "Another turn read replaced this request.",
					outcomeIsUncertain: false
				)),
				observedAt: model.conversations.cacheTime,
				preview: nil,
				model: &model,
				result: &result
			)
			if operation.isWindow
			{
				model.conversations.turnReferenceIndices[threadID]?.windowQueue = index.windowQueue
			}
			if previous.producer != producer
			{
				result.effects.append(.cancel(previous.producer.context))
			}
		}
		enforceCacheLimits(model: &model)
		touchTurn(
			operation.reference.id,
			threadID: threadID,
			model: &model
		)
		if operation.isPreview
		{
			model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = operation
			model.conversations.turnReferenceIndices[threadID]?
				.previewErrors[operation.reference.id] = nil
		}
		else if operation.isWindow
		{
			model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = operation
			model.conversations.turnReferenceIndices[threadID]?.windowError = nil
			model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll
			{
				$0.id == operation.reference.id
			}
		}
		else
		{
			model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
			model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = nil
			if let window = index.pendingWindowRead,
				index.pendingPreviewPromotion?.consumer != window
			{
				result.effects.append(.cancel(window.context))
			}
			model.conversations.pendingTurnReads[threadID] = operation
		}
		if !operation.isPreview,
			let cached = model.conversations.turnReferenceIndices[threadID]?
			.previewTurns[operation.reference.id]
		{
			receiveTurnContents(
				operation,
				observation: .succeeded(cached),
				observedAt: model.conversations.cacheTime,
				preview: nil,
				model: &model,
				result: &result
			)
		}
		else if !operation.isPreview, let producer
		{
			let promotion = ConversationTurnReadPromotion(
				producer: producer,
				consumer: operation
			)
			model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = promotion
			result.effects.append(.promoteTurnContents(promotion))
		}
		else
		{
			result.effects.append(.readTurnContents(operation))
		}
	}

	static func receiveTurnContents(
		_ operation: ConversationTurnReadOperation,
		observation: OperationResult<CodexTurn>,
		observedAt: Date,
		preview: ConversationTurnPreview?,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		), let threadID = operation.context.threadID
		else
		{
			return
		}
		let index = model.conversations.turnReferenceIndices[threadID]
		let promotion = index?.pendingPreviewPromotion
		let pending = operation.isPreview ? index?.pendingPreviewRead
			: operation.isWindow ? index?.pendingWindowRead
			: model.conversations.pendingTurnReads[threadID]
		guard pending == operation || promotion?.producer == operation
		else
		{
			return
		}
		model.conversations.cacheTime = max(
			model.conversations.cacheTime,
			observedAt
		)
		if operation.isPreview
		{
			if index?.pendingPreviewRead == operation
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
			}
			if let promotion, promotion.producer == operation
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = nil
				finishPromotedTurnRead(
					promotion,
					observation: observation,
					observedAt: observedAt,
					model: &model,
					result: &result
				)
			}
		}
		else if operation.isWindow
		{
			model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = nil
		}
		else
		{
			model.conversations.pendingTurnReads[threadID] = nil
		}
		if let promotion, promotion.consumer == operation
		{
			model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = nil
			if index?.pendingPreviewRead == promotion.producer
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
			}
			result.effects.append(.cancel(promotion.producer.context))
		}
		guard operation.commandRevision == model.execution.commandEventRevisions[
			threadID,
			default: 0
		]
		else
		{
			if operation.isWindow
			{
				model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
			}
			if !operation.isPreview
			{
				result.domainEvents.append(.conversationHistoryFinished(
					.turn(operation),
					.succeeded(false)
				))
			}
			return
		}
		if operation.isPreview
		{
			guard model.conversations.selectedConversation == .thread(threadID)
			else
			{
				return
			}
			switch observation
			{
			case .succeeded(let turn) where turn.id == operation.reference.id:
				if let preview, preview.turnID == turn.id
				{
					cachePreview(
						turn,
						preview: preview,
						threadID: threadID,
						model: &model
					)
					model.conversations.turnReferenceIndices[threadID]?.previewErrors[turn.id] = nil
					result.effects.append(.captureConversationRead(.previewExpiry(
						ConversationReadScope(
							workspace: model.identity,
							generation: model.connection.generation,
							threadID: threadID
						)
					)))
				}
			case .failed:
				model.conversations.turnReferenceIndices[threadID]?
					.previewErrors[operation.reference.id] =
					"Could not load this turn. Hover to retry."
			default:
				model.conversations.turnReferenceIndices[threadID]?
					.previewErrors[operation.reference.id] = "Could not load this turn."
			}
			enforceCacheLimits(model: &model)
			return
		}
		if operation.isWindow, model.conversations.selectedConversation != .thread(threadID)
		{
			model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
			return
		}
		let accepted: OperationResult<Bool>
		switch observation
		{
		case .failed(let failure): accepted = .failed(failure)
		case .succeeded(let turn) where turn.id == operation.reference.id:
			insertReferencedTurn(
				turn,
				threadID: threadID,
				model: &model
			)
			discardHoverContent(
				turn.id,
				threadID: threadID,
				model: &model
			)
			model.conversations.contentRevisions[threadID, default: 0] += 1
			result.domainEvents.append(.conversationContentChanged)
			accepted = .succeeded(true)
		default:
			accepted = .failed(OperationFailure(
				message: "Codex returned a different turn.",
				outcomeIsUncertain: false
			))
		}
		if operation.isWindow
		{
			if let failure = accepted.failure
			{
				model.conversations.turnReferenceIndices[threadID]?.windowError = failure.message
				model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
			}
			else
			{
				enforceCacheLimits(model: &model)
				readNextWindowTurn(
					threadID: threadID,
					model: &model,
					result: &result
				)
			}
		}
		else
		{
			result.domainEvents.append(.conversationHistoryFinished(
				.turn(operation),
				accepted
			))
		}
	}

	private static func finishPromotedTurnRead(
		_ promotion: ConversationTurnReadPromotion,
		observation: OperationResult<CodexTurn>,
		observedAt: Date,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard let threadID = promotion.consumer.context.threadID
		else
		{
			return
		}
		let consumer = promotion.consumer
		let pending = consumer.isWindow
			? model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead
			: model.conversations.pendingTurnReads[threadID]
		guard pending == consumer
		else
		{
			return
		}
		if model.conversations.selectedConversation == .thread(threadID),
			consumer.commandRevision == model.execution.commandEventRevisions[threadID, default: 0],
			case .succeeded(let turn) = observation, turn.id == consumer.reference.id,
			!turn.itemsAreComplete
		{
			result.effects.append(.readTurnContents(consumer))
			return
		}
		let completion: OperationResult<CodexTurn> =
			model.conversations.selectedConversation == .thread(threadID) ? observation
				: .failed(OperationFailure(
					message: "The displayed conversation changed before this turn was loaded.",
					outcomeIsUncertain: false
				))
		receiveTurnContents(
			consumer,
			observation: completion,
			observedAt: observedAt,
			preview: nil,
			model: &model,
			result: &result
		)
	}

	static func retireInactiveTurnPromotions(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		for threadID in model.conversations.turnReferenceIndices.keys
			where model.conversations.selectedConversation != .thread(threadID)
		{
			guard let promotion = model.conversations.turnReferenceIndices[threadID]?
				.pendingPreviewPromotion
			else
			{
				continue
			}
			model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = nil
			if model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead == promotion
				.producer
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
			}
			result.effects.append(.cancel(promotion.producer.context))
			receiveTurnContents(
				promotion.consumer,
				observation: .failed(OperationFailure(
					message: "The displayed conversation changed before this turn was loaded.",
					outcomeIsUncertain: false
				)),
				observedAt: model.conversations.cacheTime,
				preview: nil,
				model: &model,
				result: &result
			)
		}
	}
}
