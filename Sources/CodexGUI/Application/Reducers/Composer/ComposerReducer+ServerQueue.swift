import Foundation

extension ComposerReducer
{
	static func observeServerQueues(
		_ action: WorkspaceAction,
		model: inout WorkspaceModel
	)
	{
		switch action
		{
		case .execution(.backendObserved(
			let context,
			.threadQueueChanged(let threadID),
			_
		)):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			let conversation = ConversationKey.thread(threadID)
			var state = model.composer.serverQueues[conversation] ?? ServerQueueState()
			state.revision += 1
			state.needsRefresh = true
			model.composer.serverQueues[conversation] = state
		case .execution(.backendObserved(
			let context,
			.turnStarted(
				let threadID,
				_
			),
			_
		)):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			let conversation = ConversationKey.thread(threadID)
			if model.composer.serverQueues[conversation]?.awaitingStartedTurn == true
			{
				model.composer.serverQueues[conversation]?.awaitingStartedTurn = false
				model.composer.drafts[conversation]?.queuePaused = false
			}
		case .connection(.disconnected(
			let workspace,
			_,
			_
		)):
			guard workspace == model.identity
			else
			{
				return
			}
			for conversation in model.composer.serverQueues.keys
			{
				model.composer.serverQueues[conversation]?.pending = nil
				model.composer.serverQueues[conversation]?.needsRefresh = true
				model.composer.serverQueues[conversation]?.revision += 1
			}
		case .composer(.conversationRestored(
			_,
			let conversation,
			_,
			_
		)):
			model.composer.serverQueues[conversation]?.needsRefresh = true
		default: break
		}
	}

	static func reduceServerQueue(
		_ action: ComposerAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .queuedSteeringDetached(let operation):
			guard valid(
				operation.context,
				model
			),
				model.execution(for: operation.submission.conversation)
				.pendingSteering == operation.context,
				var draft = model.composer.drafts[operation.submission.conversation],
				let index = draft.queuedMessages
				.firstIndex(where:
					{
						$0.id == operation.submission.queuedMessageID
					})
			else
			{
				return
			}
			draft.queuedMessages[index].serverID = nil
			draft.queuedMessages[index].steeringPhase = .sending
			draft.queuedMessages[index].enqueueUncertain = true
			draft.revision += 1
			model.composer.serverQueues[operation.submission.conversation]?.entries.removeAll
			{
				$0.localID == operation.submission.queuedMessageID
			}
			persist(
				draft,
				conversation: operation.submission.conversation,
				context: OperationContext(
					workspace: operation.context.workspace,
					generation: operation.context.generation,
					requestID: UUID(),
					threadID: operation.context.threadID
				),
				model: &model,
				result: &result
			)
		case .serverQueueRequested(let operation):
			let conversation = operation.conversation
			guard valid(
				operation.context,
				model
			),
				operation.context.threadID == conversation.threadID,
				model.connection.isConnected
			else
			{
				return
			}
			var state = model.composer.serverQueues[conversation] ?? ServerQueueState()
			guard state.pending == nil, operation.revision == state.revision + 1
			else
			{
				return
			}
			var scoped = model
			scoped.conversations.selectedConversation = conversation
			let eligibility = WorkspaceEligibility(model: scoped)
			guard !operation
				.isMutation ||
				(eligibility.ownerAvailable && !model.conversations.showingArchived && model
					.conversations.pendingSelection == nil && model.conversations
					.pendingManagement == nil)
			else
			{
				return
			}
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			switch operation.command
			{
			case .refresh: break
			case .add(var message):
				guard state.authority == .server, eligibility.canQueue,
						draft.revision == operation.draftRevision,
						draft.text == message.text, draft.context == message.context
				else
				{
					return
				}
				message.enqueueUncertain = true
				draft.queuedMessages.append(message)
				state.attemptedEnqueueID = message.id
			case .update(let message):
				guard state.authority == .server, eligibility.canResubmitQueuedMessage,
						draft.queuedMessageEdit?.message.id == message.id
				else
				{
					return
				}
			case .delete(let id):
				guard state.authority == .server,
						draft.queuedMessages.contains(where:
						{
							$0.id == id
						})
				else
				{
					return
				}
			case .reorder(let ids):
				guard state.authority == .server, ComposerQueueOrdering.isPermutation(
					ids,
					of: draft.queuedMessages
				),
					draft.queuedMessageEdit == nil
				else
				{
					return
				}
			case .resume:
				guard state.authority == .server, eligibility.canResumeQueue
				else
				{
					return
				}
			}
			state.pending = operation
			state.revision = operation.revision
			state.needsRefresh = false
			model.composer.serverQueues[conversation] = state
			model.composer.automaticQueueConversations.remove(conversation)
			if case .add = operation.command
			{
				persist(
					draft,
					conversation: conversation,
					context: operation.context,
					model: &model,
					result: &result
				)
			}
			result.effects.append(.serverQueue(operation))

		case .serverQueueEnqueueBegan(
			let operation,
			let id
		):
			guard valid(
				operation.context,
				model
			),
				model.composer.serverQueues[operation.conversation]?.pending?.context == operation
				.context,
				var draft = model.composer.drafts[operation.conversation],
				let index = draft.queuedMessages.firstIndex(where:
					{
						$0.id == id
					})
			else
			{
				return
			}
			draft.queuedMessages[index].enqueueUncertain = true
			model.composer.serverQueues[operation.conversation]?.attemptedEnqueueID = id
			persist(
				draft,
				conversation: operation.conversation,
				context: operation.context,
				model: &model,
				result: &result
			)

		case .serverQueueMutationAccepted(
			let operation,
			let entry
		):
			let conversation = operation.conversation
			guard valid(
				operation.context,
				model
			),
				var state = model.composer.serverQueues[conversation],
				state.pending?.context == operation.context,
				var draft = model.composer.drafts[conversation]
			else
			{
				return
			}
			if let entry
			{
				state.entries.removeAll
				{
					$0.id == entry.id
				}
				state.entries.append(entry)
				var message = operation.messages.first
				{
					$0.id == entry.localID
				}
				if case .add(let added) = operation.command
				{
					message = added
				}
				if case .update(let updated) = operation.command
				{
					message = updated
				}
				if var message
				{
					message.serverID = entry.id
					message.enqueueUncertain = false
					if let index = draft.queuedMessages
						.firstIndex(where:
							{
								$0.id == message.id
							})
					{
						draft.queuedMessages[index] = message
					}
					if let edit = draft.queuedMessageEdit, edit.message.id == message.id
					{
						if draft.revision == operation.draftRevision
						{
							draft.queuedMessages.insert(
								message,
								at: min(
									edit.position,
									draft.queuedMessages.count
								)
							)
							draft.queuedMessageEdit = nil
							draft.text = ""
							draft.context = []
						}
						else
						{
							draft.queuedMessageEdit = QueuedComposerEdit(
								message: message,
								position: edit.position
							)
						}
					}
					if case .add = operation.command, draft.revision == operation.draftRevision,
						draft.text == message.text, draft.context == message.context
					{
						draft.text = ""
						draft.context = []
					}
				}
				state.attemptedEnqueueID = nil
			}
			else
			{
				switch operation.command
				{
				case .delete(let id): draft.queuedMessages.removeAll
				{
					$0.id == id
				}; state.entries
				.removeAll
				{
					$0.localID == id
				}
				case .reorder(let ids):
					draft.queuedMessages = ComposerQueueOrdering.reordered(
						draft.queuedMessages,
						by: ids
					)
				case .resume: draft.queuePaused = false
				default: break
				}
			}
			draft.revision += 1
			model.composer.serverQueues[conversation] = state
			persist(
				draft,
				conversation: conversation,
				context: operation.context,
				model: &model,
				result: &result
			)

		case .serverQueueFinished(
			let operation,
			let observation
		):
			let conversation = operation.conversation
			guard valid(
				operation.context,
				model
			),
				var state = model.composer.serverQueues[conversation],
				state.pending?.context == operation.context
			else
			{
				return
			}
			state.pending = nil
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			switch observation
			{
			case .failed(let failure):
				state.lastFailure = failure
				state.needsRefresh = !failure.outcomeIsUncertain && operation.isMutation
				if let id = state.attemptedEnqueueID, !failure.outcomeIsUncertain,
					let index = draft.queuedMessages.firstIndex(where:
					{
						$0.id == id
					})
				{
					if case .add = operation.command
					{
						draft.queuedMessages.remove(at: index)
					}
					else
					{
						draft.queuedMessages[index].enqueueUncertain = false
					}
				}
				if case .resume = operation
					.command
				{
					draft.queuePaused = !draft.queuedMessages.isEmpty
				}
			case .succeeded(let response):
				if response.unsupported
				{
					state.authority = draft.queuedMessages
						.contains(where:
							{
								$0.serverID != nil || $0.enqueueUncertain == true
							}) ?
						.server : .local
					state.needsRefresh = false
				}
				else
				{
					state.authority = .server
					if let entries = response.entries, state.revision == operation.revision
					{
						let existing =
							Dictionary(uniqueKeysWithValues: (draft
									.queuedMessages +
									(draft.queuedMessageEdit.map
									{
										[$0.message]
									} ?? []))
								.map
								{
									(
										$0.id,
										$0
									)
								})
						let oldEntries = Dictionary(uniqueKeysWithValues: state.entries.map
						{
							(
								$0.localID,
								$0
							)
						})
						let ids = Set(entries.map(\.localID))
						let consumed = draft.queuedMessages
							.filter
							{
								($0.serverID != nil && $0.steeringPhase == nil || response
									.consumedClientIDs
									.contains($0.id.uuidString)) && !ids.contains($0.id)
							}
						mergeReferences(
							consumed.flatMap(\.context),
							conversation: conversation,
							model: &model
						)
						var remoteMessages = entries.map
						{
							entry -> QueuedComposerMessage in
							var message = existing[entry.localID] ?? QueuedComposerMessage(
								id: entry.localID,
								text: entry.preview,
								context: entry.contextItems,
								modelID: nil,
								effort: nil,
								preferences: .standard,
								skills: [],
								collaborationMode: nil,
								serviceTier: nil
							)
							if let old = oldEntries[entry.localID],
								old.inputJSON != entry
								.inputJSON
							{
								message = message.editing(
									text: entry.preview,
									context: entry.contextItems
								)
							}
							message.serverID = entry.id
							message.enqueueUncertain = message.steeringPhase == .sending
							if message.steeringPhase == .deleting
							{
								message.steeringPhase = nil
							}
							return message
						}
						if let edit = draft.queuedMessageEdit
						{
							if ids
								.contains(edit.message.id)
							{
								remoteMessages.removeAll
								{
									$0.id == edit.message.id
								}
							}
							else
							{
								draft.queuedMessageEdit = nil
							}
						}
						let legacy = draft.queuedMessages
							.filter
							{
								($0.serverID == nil || $0.steeringPhase != nil) && !ids
									.contains($0.id) && !response
									.consumedClientIDs.contains($0.id.uuidString)
							}
						let held = legacy.map
						{
							original in
							var message = original
							if message.steeringPhase != nil
							{
								message.serverID = nil
								message.enqueueUncertain = message.steeringPhase != .ready
							}
							return message
						}
						draft.queuedMessages = remoteMessages + held
						state.entries = entries
						if !consumed.isEmpty
						{
							draft.queuePaused = false
						}
						if !draft.queuedMessages.isEmpty && !model.execution(for: conversation)
							.isTaskActive && !response.resumed && model.execution(for: conversation)
							.agentOutcome != .completed
						{
							draft.queuePaused = true
						}
					}
					else if response.entries != nil
					{
						state.needsRefresh = true
					}
					state.lastFailure = response.refreshFailure
					if response.resumed
					{
						draft.queuePaused = false
						state.awaitingStartedTurn = response.turn == nil && !model
							.execution(for: conversation).isTaskActive
					}
					if let turn = response.turn
					{
						draft.queuePaused = false
						result.domainEvents.append(.backendObserved(.turnStarted(
							threadId: conversation.threadID!,
							turn: turn
						)))
					}
				}
			}
			state.attemptedEnqueueID = nil
			draft.revision += 1
			model.composer.serverQueues[conversation] = state
			model.composer.automaticQueueConversations.remove(conversation)
			persist(
				draft,
				conversation: conversation,
				context: operation.context,
				model: &model,
				result: &result
			)
		default: break
		}
	}
}
