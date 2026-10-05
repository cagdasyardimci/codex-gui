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
				let anchorPosition = index.references.firstIndex(where:
				{
					$0.id == anchor
				})
		else
		{
			return
		}
		let windowStart = max(
			0,
			min(
				anchorPosition - ConversationCachePolicy.contentPageSize / 2,
				index.references.count - ConversationCachePolicy.contentPageSize
			)
		)
		let windowEnd = min(
			index.references.count,
			windowStart + ConversationCachePolicy.contentPageSize
		)
		let loadedTurnIDs = Set(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) ?? [])
		let windowReferences = Array(index.references[windowStart ..< windowEnd].enumerated())
		let unloadedReferences = windowReferences.filter
		{
			!loadedTurnIDs.contains($0.element.id) && $0.element.id != index.pendingWindowRead?
				.reference.id
		}
		let referencesNearestAnchor = unloadedReferences.sorted
		{
			let firstDistance = abs(windowStart + $0.offset - anchorPosition)
			let secondDistance = abs(windowStart + $1.offset - anchorPosition)
			return firstDistance < secondDistance
		}
		index.windowQueue = referencesNearestAnchor.map(\.element)
		index.windowError = nil
		model.conversations.turnReferenceIndices[threadID] = index
		if anchorPosition < ConversationCachePolicy.contentPageSize / 2,
			let cursor = index.nextCursor, index.pendingRead == nil
		{
			result.effects.append(.captureConversationRead(.references(
				ConversationReadScope(
					workspace: model.identity,
					generation: model.connection.generation,
					threadID: threadID
				),
				cursor: cursor
			)))
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
		let loadedTurnIDs = Set(model.conversations.content[.thread(threadID)]?.loadedTurns
			.map(\.id) ?? [])
		index.windowQueue.removeAll
		{
			loadedTurnIDs.contains($0.id)
		}
		guard !index.windowQueue.isEmpty
		else
		{
			return
		}
		let reference = index.windowQueue[0]
		model.conversations.turnReferenceIndices[threadID] = index
		result.effects.append(.captureConversationRead(.window(
			ConversationReadScope(
				workspace: model.identity,
				generation: model.connection.generation,
				threadID: threadID
			),
			reference: reference,
			commandRevision: ConversationReducer.commandRevision(
				threadID: threadID,
				model: model
			)
		)))
	}
}
