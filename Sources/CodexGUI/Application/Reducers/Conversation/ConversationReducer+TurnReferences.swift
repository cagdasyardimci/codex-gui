import Foundation

extension ConversationReducer
{
	static func ensureTurnReferences(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		retireInactiveTurnPromotions(
			model: &model,
			result: &result
		)
		guard let threadID = model.conversations.selectedConversation.threadID,
				model.connection.isConnected,
				model.conversations.turnReferenceIndices[threadID]?.hasLoadedPage != true,
				model.conversations.turnReferenceIndices[threadID]?.pendingRead == nil
		else
		{
			return
		}
		result.effects.append(.captureConversationRead(.references(
			ConversationReadScope(
				workspace: model.identity,
				generation: model.connection.generation,
				threadID: threadID
			),
			cursor: nil
		)))
	}

	static func reduceTurnNavigation(
		_ action: ConversationsAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .previewExpiryRequested(let context):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			result.effects.append(.expireTurnPreviews(context))
		case .cacheExpired(
			let context,
			let observedAt
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			model.conversations.cacheTime = max(
				model.conversations.cacheTime,
				observedAt
			)
			enforceCacheLimits(model: &model)
		case .previewAccessed(
			let context,
			let turnID,
			let observedAt
		):
			guard valid(
				context,
				model
			), let threadID = context.threadID,
			model.conversations.selectedConversation == .thread(threadID)
			else
			{
				return
			}
			model.conversations.cacheTime = max(
				model.conversations.cacheTime,
				observedAt
			)
			touchTurn(
				turnID,
				threadID: threadID,
				model: &model
			)
			model.conversations.turnReferenceIndices[threadID]?.previewAccess[turnID] =
				model.conversations.cacheAccessCounter
			enforceCacheLimits(model: &model)
		case .viewportChanged(
			let context,
			let viewport,
			let observedAt
		):
			guard valid(
				context,
				model
			), let threadID = context.threadID,
			model.conversations.selectedConversation == .thread(threadID)
			else
			{
				return
			}
			model.conversations.cacheTime = max(
				model.conversations.cacheTime,
				observedAt
			)
			model.conversations.turnReferenceIndices[threadID]?.viewport = viewport
			if model.contextNavigation.pendingJump == nil
			{
				model.conversations.turnReferenceIndices[threadID]?.navigationProtection = nil
			}
			for turnID in viewport.turnIDs
			{
				touchTurn(
					turnID,
					threadID: threadID,
					model: &model
				)
			}
			enforceCacheLimits(model: &model)
			queueReadingWindow(
				threadID: threadID,
				model: &model,
				result: &result
			)
		case .turnReferencesRequested(let operation):
			requestTurnReferences(
				operation,
				model: &model,
				result: &result
			)
		case .turnReferencesReceived(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID,
			var index = model.conversations.turnReferenceIndices[threadID],
			index.pendingRead == operation
			else
			{
				return
			}
			index.pendingRead = nil
			switch observation
			{
			case .failed(let failure):
				index.error = "Could not load turn references: \(failure.message)"
			case .succeeded(let page):
				index.error = nil
				var seen: Set<String> = []
				let incoming = page.references.filter
				{
					seen.insert($0.id).inserted
				}
				let retained = index.references.filter
				{
					!seen.contains($0.id)
				}
				index.references = operation
					.cursor == nil ? retained + incoming : incoming + retained
				index.hasLoadedPage = true
				index.nextCursor = page.nextCursor == operation.cursor ? nil : page.nextCursor
			}
			model.conversations.turnReferenceIndices[threadID] = index
			refreshCacheGaps(
				threadID: threadID,
				model: &model
			)
			queueReadingWindow(
				threadID: threadID,
				model: &model,
				result: &result
			)
		case .turnContentsRequested(let operation):
			requestTurnContents(
				operation,
				model: &model,
				result: &result
			)
		case .turnContentsReceived(
			let operation,
			let observation,
			let observedAt,
			let preview
		):
			receiveTurnContents(
				operation,
				observation: observation,
				observedAt: observedAt,
				preview: preview,
				model: &model,
				result: &result
			)
		default: break
		}
	}

	static func requestTurnReferences(
		_ operation: TurnReferenceReadOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		), let threadID = operation.context.threadID,
		model.connection.isConnected, let path = model.identity.canonicalCheckoutPath,
		model.conversations.selectedConversation == .thread(threadID),
		model.conversations.boundThreadID == nil || model.conversations
		.boundThreadID == threadID
		else
		{
			return
		}
		// A reference page has no cwd of its own. Admit it from an already
		// validated history or a thread summary belonging to this checkout.
		let summary = model.conversations.threads.first
		{
			$0.id == threadID
		}
		let ownsSummary = operation.summaryOwnership.map
		{
			$0.canonicalCheckoutPath == path && $0.summaryCWD == summary?.cwd
		} == true
		guard ownsSummary || model.conversations.content[.thread(threadID)]?
			.hasLoadedHistory == true
		else
		{
			return
		}
		var index = model.conversations.turnReferenceIndices[threadID] ?? TurnReferenceIndex()
		guard index.pendingRead == nil,
				operation.cursor == nil || operation.cursor == index.nextCursor
		else
		{
			return
		}
		index.pendingRead = operation
		index.error = nil
		model.conversations.turnReferenceIndices[threadID] = index
		result.effects.append(.readTurnReferences(operation))
	}

	static func insertReferencedTurn(
		_ turn: CodexTurn,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		let referenceIDs = model.conversations.turnReferenceIndices[threadID]?.references
			.map(\.id) ?? []
		let positions = Dictionary(uniqueKeysWithValues: referenceIDs.enumerated().map
		{
			(
				$0.element,
				$0.offset
			)
		})
		let position = positions[turn.id] ?? 0
		let execution = model.execution(for: .thread(threadID))
		let livePrefix = execution.activeThreadID == threadID ? execution.activeTurnID
			.map
			{
				$0 + ":"
			} : nil
		ConversationContentReducer.updateContent(
			for: threadID,
			model: &model
		)
		{
			content in
			guard !content.loadedTurns.contains(where:
				{
					$0.id == turn.id
				})
			else
			{
				return
			}
			let streamed = content.entries
				.filter
				{
					entry in livePrefix.map(entry.id.hasPrefix) == true
				}
			let insertion = content.loadedTurns
				.firstIndex
				{
					existing in positions[existing.id].map
					{
						$0 > position
					} == true
				}
				?? content.loadedTurns.endIndex
			content.loadedTurns.insert(
				turn,
				at: insertion
			)
			content.content.turnTimings[turn.id] = ConversationTurnTiming(
				turn: turn,
				previous: nil
			)
			content.entries = ConversationContentReducer.entries(for: content.loadedTurns)
			for entry in streamed
			{
				if let index = content.entries.firstIndex(where:
					{
						$0.id == entry.id
					})
				{
					content.entries[index] = entry
				}
				else
				{
					content.entries.append(entry)
				}
			}
			ConversationContentReducer.reviewSourceChanged(
				content: &content,
				threadID: threadID
			)
		}
		refreshCacheGaps(
			threadID: threadID,
			model: &model
		)
	}
}
