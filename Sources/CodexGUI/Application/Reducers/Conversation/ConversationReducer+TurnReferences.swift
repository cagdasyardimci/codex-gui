import Foundation

extension ConversationReducer
{
	static func ensureTurnReferences(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard let threadID = model.conversations.selectedConversation.threadID,
				model.connection.isConnected,
				model.conversations.turnReferenceIndices[threadID]?.hasLoadedPage != true
		else
		{
			return
		}
		requestTurnReferences(
			TurnReferenceReadOperation(
				context: OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID(),
					threadID: threadID
				),
				cursor: nil
			),
			model: &model,
			result: &result
		)
	}

	static func reduceTurnNavigation(
		_ action: ConversationsAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
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
			queueReadingWindow(
				threadID: threadID,
				model: &model,
				result: &result
			)
		case .turnContentsRequested(let operation):
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID,
			model.conversations.selectedConversation == .thread(threadID),
			model.conversations.boundThreadID == nil || model.conversations
			.boundThreadID == threadID,
			model.conversations.turnReferenceIndices[threadID]?.references
			.contains(operation.reference) == true,
			operation.commandRevision == model.execution.commandEventRevisions[
				threadID,
				default: 0
			]
			else
			{
				return
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
			}
			else
			{
				model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
				model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = nil
				model.conversations.pendingTurnReads[threadID] = operation
			}
			if !operation.isPreview,
				let cached = model.conversations.turnReferenceIndices[threadID]?
				.previewTurns[operation.reference.id]
			{
				reduceTurnNavigation(
					.turnContentsReceived(
						operation,
						.succeeded(cached)
					),
					model: &model,
					result: &result
				)
			}
			else if !operation.isPreview,
					model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead?
					.reference.id == operation.reference.id
			{
				// The preview's existing fetch now also serves the pending jump.
			}
			else
			{
				result.effects.append(.readTurnContents(operation))
			}
		case .turnContentsReceived(
			let operation,
			let observation,
			let observedAt
		):
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID,
			(operation.isPreview
				? model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead
				: operation.isWindow
				? model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead
				: model.conversations.pendingTurnReads[threadID]) == operation
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
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
			}
			else if operation.isWindow
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = nil
			}
			else
			{
				model.conversations.pendingTurnReads.removeValue(forKey: threadID)
			}
			guard operation.commandRevision == model.execution.commandEventRevisions[
				threadID,
				default: 0
			]
			else
			{
				result.domainEvents.append(.conversationHistoryFinished(
					.turn(operation),
					.succeeded(false)
				))
				return
			}
			if operation.isWindow
			{
				guard model.conversations.selectedConversation == .thread(threadID)
				else
				{
					return
				}
				switch observation
				{
				case .succeeded(let turn) where turn.id == operation.reference.id:
					insertReferencedTurn(
						turn,
						threadID: threadID,
						model: &model
					)
					model.conversations.contentRevisions[threadID, default: 0] += 1
					result.domainEvents.append(.conversationContentChanged)
					enforceCacheLimits(model: &model)
					readNextWindowTurn(
						threadID: threadID,
						model: &model,
						result: &result
					)
				case .failed(let failure):
					model.conversations.turnReferenceIndices[threadID]?.windowError = failure
						.message
					model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
				default: break
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
					cachePreview(
						turn,
						threadID: threadID,
						model: &model
					)
					model.conversations.turnReferenceIndices[threadID]?.previewErrors[turn.id] = nil
					result.effects.append(.expireTurnPreviews(OperationContext(
						workspace: model.identity,
						generation: model.connection.generation,
						requestID: UUID(),
						threadID: threadID
					)))
				case .failed:
					model.conversations.turnReferenceIndices[threadID]?
						.previewErrors[operation.reference.id] =
						"Could not load this turn. Hover to retry."
				default:
					model.conversations.turnReferenceIndices[threadID]?
						.previewErrors[operation.reference.id] = "Could not load this turn."
				}
				if let navigation = model.conversations.pendingTurnReads[threadID],
					navigation.reference.id == operation.reference.id
				{
					if case .succeeded(let turn) = observation, !turn.itemsAreComplete
					{
						result.effects.append(.readTurnContents(navigation))
					}
					else
					{
						reduceTurnNavigation(
							.turnContentsReceived(
								navigation,
								observation
							),
							model: &model,
							result: &result
						)
					}
				}
				enforceCacheLimits(model: &model)
				return
			}
			switch observation
			{
			case .failed(let failure):
				result.domainEvents.append(.conversationHistoryFinished(
					.turn(operation),
					.failed(failure)
				))
			case .succeeded(let turn):
				guard turn.id == operation.reference.id
				else
				{
					result.domainEvents.append(.conversationHistoryFinished(
						.turn(operation),
						.failed(OperationFailure(
							message: "Codex returned a different turn.",
							outcomeIsUncertain: false
						))
					))
					return
				}
				insertReferencedTurn(
					turn,
					threadID: threadID,
					model: &model
				)
				model.conversations.turnReferenceIndices[threadID]?.previewTurns[turn.id] = nil
				model.conversations.turnReferenceIndices[threadID]?.previewCachedAt[turn.id] = nil
				model.conversations.contentRevisions[threadID, default: 0] += 1
				result.domainEvents.append(.conversationContentChanged)
				result.domainEvents.append(.conversationHistoryFinished(
					.turn(operation),
					.succeeded(true)
				))
			}
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
		let ownsSummary = summary.map
		{
			(try? CheckoutIdentity.validate(
				cwd: $0.cwd,
				expectedDirectory: URL(fileURLWithPath: path)
			)) != nil
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
		let livePrefix = model.execution.activeThreadID == threadID ? model.execution.activeTurnID
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
	}
}
