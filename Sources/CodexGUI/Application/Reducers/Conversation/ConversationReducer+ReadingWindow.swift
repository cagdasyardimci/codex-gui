import Foundation

extension ConversationReducer
{
	static func queueReadingWindow(
		threadID: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard model.connection.isConnected, !model.conversations.cacheOverBudget,
				model.conversations.selectedConversation == .thread(threadID),
				model.conversations.pendingTurnReads[threadID] == nil,
				var index = model.conversations.turnReferenceIndices[threadID],
				let anchor = index.viewport.anchorTurnID,
				let center = index.references.firstIndex(where:
				{
					$0.id == anchor
				})
		else
		{
			return
		}
		let lower = max(
			0,
			min(
				center - ConversationCachePolicy.contentPageSize / 2,
				index.references.count - ConversationCachePolicy.contentPageSize
			)
		)
		let upper = min(
			index.references.count,
			lower + ConversationCachePolicy.contentPageSize
		)
		let loaded = Set(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) ?? [])
		index.windowQueue = Array(index.references[lower ..< upper].enumerated())
			.filter
			{
				!loaded.contains($0.element.id) && $0.element.id != index.pendingWindowRead?
					.reference.id
			}
			.sorted
			{
				abs(lower + $0.offset - center) < abs(lower + $1.offset - center)
			}
			.map(\.element)
		index.windowError = nil
		model.conversations.turnReferenceIndices[threadID] = index
		if center < ConversationCachePolicy.contentPageSize / 2,
			let cursor = index.nextCursor, index.pendingRead == nil
		{
			requestTurnReferences(
				TurnReferenceReadOperation(
					context: OperationContext(
						workspace: model.identity,
						generation: model.connection.generation,
						requestID: UUID(),
						threadID: threadID
					),
					cursor: cursor
				),
				model: &model,
				result: &result
			)
		}
		readNextWindowTurn(
			threadID: threadID,
			model: &model,
			result: &result
		)
	}

	static func readNextWindowTurn(
		threadID: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard model.connection.isConnected, !model.conversations.cacheOverBudget,
				model.conversations.selectedConversation == .thread(threadID),
				model.conversations.pendingTurnReads[threadID] == nil,
				var index = model.conversations.turnReferenceIndices[threadID],
				index.pendingWindowRead == nil
		else
		{
			return
		}
		let loaded = Set(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) ?? [])
		index.windowQueue.removeAll
		{
			loaded.contains($0.id)
		}
		guard !index.windowQueue.isEmpty
		else
		{
			return
		}
		let reference = index.windowQueue.removeFirst()
		model.conversations.turnReferenceIndices[threadID] = index
		reduceTurnNavigation(
			.turnContentsRequested(ConversationTurnReadOperation(
				context: OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID(),
					threadID: threadID
				),
				reference: reference,
				commandRevision: model.execution.commandEventRevisions[threadID, default: 0],
				isWindow: true
			)),
			model: &model,
			result: &result
		)
	}
}
