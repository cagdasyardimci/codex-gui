import Foundation

/// One value owner for conversation selection, canonical history and ordered streaming content.
@MainActor
enum ConversationReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)
	struct AcceptedHistory
	{
		let operation: ConversationReadOperation
		let executionAction: ExecutionAction
	}
	struct AcceptedSelection
	{
		let executionAction: ExecutionAction
		let effectIndex: Int
		let domainEventIndex: Int
		let presentationCommandIndex: Int
	}
	static func acceptsNewChat(
		_ context: OperationContext,
		model: WorkspaceModel
	) -> Bool
	{
		valid(
			context,
			model
		) && model.conversations.boundThreadID == nil
			&& model.conversations.pendingManagement == nil
			&& model.conversations.pendingProjectArchive == nil
			&& WorkspaceLifecycleReducer.accepts(
				.conversations(.newChatOpened(context)),
				model: model
			)
	}
	static func commandRevision(
		threadID: String,
		model: WorkspaceModel
	) -> Int
	{
		model.execution(for: .thread(threadID)).commandEventRevisions[threadID, default: 0]
	}
	static func detachNewChatContent(
		lifetime: Int,
		model: inout WorkspaceModel
	)
	{
		if let content = model.conversations.content[.newChat], !content.entries.isEmpty
		{
			model.conversations.pendingNewChatContent[lifetime] = content
		}
		model.conversations.content[.newChat] = ConversationContentModel()
	}
	static func adoptPreparedSelection(
		_ key: ConversationKey,
		model: inout WorkspaceModel
	)
	{
		model.conversations.selectedConversation = key
	}
	static func valid(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
	}
	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		WorkspaceExecutionScope.reduce(
			action: action,
			model: &model
		)
		{
			model in
			reduceScoped(
				&model,
				action
			)
		}
	}

	private static func reduceScoped(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var (result, acceptedHistory, _) = reduceForComposition(
			&model,
			action
		)
		if let acceptedHistory
		{
			finishAcceptedHistory(
				acceptedHistory,
				model: &model,
				result: &result
			)
		}
		return result
	}

	static func reduceForComposition(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> (WorkspaceReduction, AcceptedHistory?, AcceptedSelection?)
	{
		var result = WorkspaceReduction()
		var acceptedHistory: AcceptedHistory?
		var acceptedSelection: AcceptedSelection?
		switch action
		{
		case .connection(.projectOpened(
			let identity,
			let selectedThreadID
		)):
			guard model.identity == identity, !model.hasActiveExecution
			else
			{
				return (result, nil, nil)
			}
			let bound = model.conversations.boundThreadID
			model.conversations = ConversationsModel()
			model.conversations.boundThreadID = bound
			model.conversations.selectedConversation = selectedThreadID
				.map(ConversationKey.thread) ?? .newChat
		case .connection(.projectRestored(
			let context,
			_,
			let selectedThreadID,
			_
		)):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			),
				model.conversations.boundThreadID == nil || model.conversations
				.boundThreadID == selectedThreadID
			else
			{
				return (result, nil, nil)
			}
			model.conversations.selectedConversation = selectedThreadID
				.map(ConversationKey.thread) ?? .newChat
		case .conversations(let intent):
			reduceConversations(
				intent,
				model: &model,
				result: &result,
				acceptedHistory: &acceptedHistory,
				acceptedSelection: &acceptedSelection
			)
		default: break
		}
		return (result, acceptedHistory, acceptedSelection)
	}

	static func finishAcceptedHistory(
		_ accepted: AcceptedHistory,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		result.domainEvents.append(.conversationHistoryFinished(
			.history(accepted.operation),
			.succeeded(true)
		))
		model.conversations.lastAppliedHistoryRequestID = accepted.operation.context.requestID
		if let threadID = accepted.operation.context.threadID
		{
			model.conversations.historyErrors[threadID] = nil
			if model.conversations.selectedConversation == .thread(threadID)
			{
				model.conversations.error = nil
			}
		}
	}

	private static func select(
		_ key: ConversationKey,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction,
		acceptedSelection: inout AcceptedSelection?
	)
	{
		model.conversations.selectedConversation = key
		model.conversations.pendingSelection = nil
		model.conversations.pendingReads = model.conversations.pendingReads.filter
		{
			$0.key.purpose != .selection
		}
		model.conversations.error = nil
		let threadID: String?
		switch key
		{
		case .newChat: threadID = nil
		case .thread(let id): threadID = id
		}
		result.domainEvents.append(.conversationSelectionChanged(threadID))
		let executionAction: ExecutionAction = threadID.map
		{
			.conversationSelected(
				threadID: $0,
				recovering: true
			)
		} ?? .conversationCleared
		acceptedSelection = AcceptedSelection(
			executionAction: executionAction,
			effectIndex: result.effects.count,
			domainEventIndex: result.domainEvents.count,
			presentationCommandIndex: result.presentationCommands.count
		)
		if !model.conversations.showingArchived
		{
			model.conversations.pendingSelectionPersistence = context
			result.effects.append(.persistConversationSelection(
				context,
				threadID: threadID
			))
		}
	}

	private static func requestHistory(
		_ operation: ConversationReadOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		), let threadID = operation.context.threadID,
		model.conversations.boundThreadID == nil || model.conversations.boundThreadID == threadID,
		operation.commandRevision == ConversationReducer.commandRevision(
			threadID: threadID,
			model: model
		),
		operation.purpose != .selection || model.conversations
		.selectedConversation == .thread(threadID)
		else
		{
			return
		}
		var captured = operation
		captured.contentRevision = model.conversations.contentRevisions[threadID, default: 0]
		model.conversations.pendingReads[operation.key] = captured
		if operation.purpose == .selection
		{
			model.conversations.pendingSelection = operation.context
		}
		result.effects.append(.readConversationHistory(captured))
	}

	private static func reduceConversations(
		_ action: ConversationsAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction,
		acceptedHistory: inout AcceptedHistory?,
		acceptedSelection: inout AcceptedSelection?
	)
	{
		switch action
		{
		case .turnReferencesRequested, .turnReferencesReceived, .turnContentsRequested,
				.turnContentsReceived, .viewportChanged, .previewAccessed, .cacheExpired,
				.previewExpiryRequested:
			reduceTurnNavigation(
				action,
				model: &model,
				result: &result
			)
		case .projectArchiveRequested(let operation):
			guard valid(
				operation.context,
				model
			),
				WorkspaceEligibility(model: model).canManageThreads,
				!model.hasActiveExecution, model.conversations.boundThreadID == nil
			else
			{
				return
			}
			model.conversations.pendingProjectArchive = operation
			model.conversations.error = nil
			result.effects.append(.archiveProjectChats(operation))
		case .projectArchiveFinished(
			let operation,
			let outcome
		):
			guard valid(
				operation.context,
				model
			),
				model.conversations.pendingProjectArchive == operation
			else
			{
				return
			}
			model.conversations.pendingProjectArchive = nil
			let archivedIDs = Set(outcome.archivedThreadIDs)
			let removedPins = model.preferences.pinnedTasks.filter
			{
				archivedIDs.contains($0.id)
			}
			model.preferences.pinnedTasks.removeAll
			{
				archivedIDs.contains($0.id)
			}
			for task in removedPins
			{
				persistTaskPin(
					task,
					pinned: false,
					context: operation.context,
					model: &model,
					result: &result
				)
			}
			model.conversations.threads.removeAll
			{
				archivedIDs.contains($0.id)
			}
			if let selected = model.conversations.selectedConversation.threadID,
				archivedIDs.contains(selected)
			{
				select(
					.newChat,
					context: operation.context,
					model: &model,
					result: &result,
					acceptedSelection: &acceptedSelection
				)
			}
			model.conversations.error = outcome.failure.map
			{
				"Could not archive all project chats: \($0.message)"
			}
			if outcome.failure == nil,
				operation.project.path == model.identity.canonicalCheckoutPath
			{
				let list = ConversationListOperation(
					context: operation.context,
					archived: model.conversations.showingArchived,
					boundThreadID: nil
				)
				model.conversations.pendingList = list
				result.effects.append(.readConversationList(list))
			}
		case .newChatRequested: break
		case .newChatOpened(let context):
			guard acceptsNewChat(
				context,
				model: model
			)
			else
			{
				return
			}
			model.conversations.showingArchived = false
			select(
				.newChat,
				context: context,
				model: &model,
				result: &result,
				acceptedSelection: &acceptedSelection
			)
		case .selectionRequested(let context):
			guard valid(
				context,
				model
			), let threadID = context.threadID,
			model.conversations.pendingManagement == nil,
			model.conversations.pendingProjectArchive == nil,
			model.conversations.boundThreadID == nil || model.conversations
			.boundThreadID == threadID
			else
			{
				return
			}
			let previous = model.conversations.selectedConversation
			if model.conversations.showingArchived && threadID == model.execution.activeThreadID
			{
				model.conversations.showingArchived = false
				model.conversations.pendingList = nil
			}
			select(
				.thread(threadID),
				context: context,
				model: &model,
				result: &result,
				acceptedSelection: &acceptedSelection
			)
			let execution = model.execution(for: .thread(threadID))
			let shouldKeepExistingHistory = execution.activeThreadID == threadID
				&& (execution.state.isBusy
					|| (!execution.needsReconciliation && previous != .thread(threadID)))

			if shouldKeepExistingHistory
			{
				return
			}
			requestHistory(
				ConversationReadOperation(
					context: context,
					commandRevision: ConversationReducer.commandRevision(
						threadID: threadID,
						model: model
					),
					purpose: .selection
				),
				model: &model,
				result: &result
			)
		case .archivedFilterRequested(
			let context,
			let archived
		):
			guard valid(
				context,
				model
			),
				model.conversations.pendingManagement == nil,
				model.conversations.pendingProjectArchive == nil
			else
			{
				return
			}
			model.conversations.showingArchived = archived
			model.conversations.pendingList = nil
			select(
				context.threadID.map(ConversationKey.thread) ?? .newChat,
				context: context,
				model: &model,
				result: &result,
				acceptedSelection: &acceptedSelection
			)
		case .threadListRequested(let operation):
			guard valid(
				operation.context,
				model
			),
				operation.archived == model.conversations.showingArchived,
				operation.boundThreadID == model.conversations.boundThreadID
			else
			{
				return
			}
			model.conversations.observedThreadNames.removeAll()
			model.conversations.pendingList = operation
			result.effects.append(.readConversationList(operation))
		case .threadListReceived(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			), let pending = model.conversations.pendingList,
			pending.context == operation.context, pending.archived == operation.archived,
			pending.boundThreadID == operation.boundThreadID,
			operation.archived == model.conversations.showingArchived,
			operation.boundThreadID == model.conversations.boundThreadID
			else
			{
				return
			}
			model.conversations.pendingList = nil
			switch observation
			{
			case .succeeded(let threads):
				model.conversations.threads = threads.map
				{
					var thread = $0
					if thread.preview?.isEmpty != false
					{
						thread.preview = model.conversations.threads
							.first(where:
								{
									$0.id == thread.id
								})?.preview
					}
					if let name = model.conversations.observedThreadNames[thread.id]
					{
						thread.name = name
					}
					return thread
				}
				for thread in model.conversations.threads
				{
					if let index = model.preferences.pinnedTasks
						.firstIndex(where:
							{
								$0.id == thread.id
							}),
						model.preferences.pinnedTasks[index] != thread
					{
						model.preferences.pinnedTasks[index] = thread
						persistTaskPin(
							thread,
							pinned: true,
							context: operation.context,
							model: &model,
							result: &result
						)
					}
				}
				model.conversations.error = nil
				result.domainEvents.append(.conversationContentChanged)
				result.domainEvents.append(.conversationListAccepted(operation))
			case .failed(let failure):
				model.conversations.error = "Could not load conversations: \(failure.message)"
			}
		case .historyRequested(let operation): requestHistory(
				operation,
				model: &model,
				result: &result
			)
		case .historyReceived(
			let operation,
			let observation
		):

			guard valid(
				operation.context,
				model
			),
				let pending = model.conversations.pendingReads[operation.key],
				pending.context == operation.context,
				pending.commandRevision == operation.commandRevision,
				pending.contentRevision == operation.contentRevision,
				let threadID = operation.context.threadID,
				operation.purpose != .selection ||
				(model.conversations.pendingSelection == operation.context && model.conversations
					.selectedConversation == .thread(threadID))
			else
			{
				return
			}
			model.conversations.pendingReads.removeValue(forKey: operation.key)
			if model.execution.pendingReconciliation?.context == operation.context
			{
				model.execution.pendingReconciliation = nil
			}
			if operation.purpose == .selection
			{
				model.conversations.pendingSelection = nil
			}
			guard ConversationReducer.commandRevision(
				threadID: threadID,
				model: model
			) == operation
				.commandRevision,
				model.conversations.contentRevisions[threadID, default: 0] == operation
				.contentRevision
			else
			{
				result.domainEvents.append(.conversationHistoryFinished(
					.history(operation),
					.succeeded(false)
				))
				return
			}
			switch observation
			{
			case .failed(let failure):
				result.domainEvents.append(.conversationHistoryFinished(
					.history(operation),
					.failed(failure)
				))
				model.conversations.historyErrors[threadID] =
					"Could not read conversation: \(failure.message)"
				if operation.purpose == .selection
				{
					model.conversations.historyErrors[threadID] =
						"Could not open conversation: \(failure.message)"
				}
				if operation.purpose == .recovery
				{
					model.execution.needsReconciliation = true
					model.execution.state = .failed
					model.execution.statusMessage =
						"Could not check the previous request: \(failure.message). "
							+ "Use Refresh or Reconnect to try again."
					model.conversations.historyErrors[threadID] = model.execution.statusMessage
				}
			case .succeeded(let detail):
				guard detail.summary.id == threadID,
						operation.purpose != .completion || model.execution
						.activeThreadID != threadID || model.execution.activeTurnID == nil
				else
				{
					result.domainEvents.append(.conversationHistoryFinished(
						.history(operation),
						.succeeded(false)
					))
					return
				}
				let recovery = ReconciliationOperation(
					context: operation.context,
					commandRevision: operation.commandRevision,
					contentOnly: operation.purpose == .search
				)
				let executionAction: ExecutionAction
				switch operation.purpose
				{
				case .completion: executionAction = .completedHistoryReceived(
						recovery,
						.succeeded(detail)
					)
				case .selection, .recovery: executionAction = .historyObserved(
						recovery,
						detail
					)
				case .search: executionAction = .historyObserved(
						recovery,
						detail
					)
				}
				acceptedHistory = AcceptedHistory(
					operation: operation,
					executionAction: executionAction
				)
			}
		case .earlierTurnsRequested(let operation):
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID,
			operation.pageScope.projectPath == model.identity.canonicalCheckoutPath,
			operation.pageScope.generation == model.connection.generation,
			operation.commandRevision == ConversationReducer.commandRevision(
				threadID: threadID,
				model: model
			),
			model.conversations.content[.thread(threadID)]?.nextTurnsCursor == operation
			.pageScope.cursor
			else
			{
				return
			}
			if let current = model.conversations.historyLoads[threadID],
				current.pageScope == operation.pageScope,
				current.commandRevision == operation.commandRevision
			{
				return
			}
			model.conversations.historyLoads[threadID] = operation
			result.effects.append(.readConversationPage(operation))
		case .earlierTurnsReceived(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID,
			let pending = model.conversations.historyLoads[threadID],
			pending.context == operation.context,
			pending.pageScope == operation.pageScope,
			pending.commandRevision == operation.commandRevision,
			operation.pageScope.projectPath == model.identity.canonicalCheckoutPath,
			operation.pageScope.generation == model.connection.generation
			else
			{
				return
			}
			model.conversations.historyLoads.removeValue(forKey: threadID)
			guard model.conversations.content[.thread(threadID)]?.nextTurnsCursor == operation
				.pageScope.cursor,
				operation.commandRevision == ConversationReducer.commandRevision(
					threadID: threadID,
					model: model
				)
			else
			{
				result.domainEvents.append(.conversationHistoryFinished(
					.page(operation),
					.succeeded(false)
				))
				return
			}
			switch observation
			{
			case .failed(let failure):
				result.domainEvents.append(.conversationHistoryFinished(
					.page(operation),
					.failed(failure)
				))
				let message = "Could not load earlier messages: \(failure.message)"
				model.conversations.historyErrors[threadID] = message
			case .succeeded(let page):
				let execution = model.execution(for: .thread(threadID))
				let liveTurnID = execution.activeThreadID == threadID ? execution.activeTurnID : nil
				ConversationContentReducer.updateContent(
					for: threadID,
					model: &model
				)
				{
					content in
					prependHistoryPage(
						page,
						operation: operation,
						liveTurnID: liveTurnID,
						threadID: threadID,
						content: &content
					)
				}
				result.domainEvents.append(.conversationContentChanged)
				model.conversations.contentRevisions[threadID, default: 0] += 1
				result.domainEvents.append(.conversationHistoryFinished(
					.page(operation),
					.succeeded(true)
				))
				model.conversations.lastAppliedPageRequestID = operation.context.requestID
				model.conversations.historyErrors[threadID] = nil
				if model.conversations.selectedConversation == .thread(threadID)
				{
					model.conversations.error = nil
				}
			}
		case .managementRequested(let operation):
			guard WorkspaceEligibility(model: model).acceptsManagement(operation)
			else
			{
				return
			}
			if case .rename(
				_,
				let name
			) = operation,
				name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			{
				model.conversations.error = "Enter a conversation name."
				return
			}
			model.conversations.pendingManagement = operation
			model.conversations.pendingManagementArchived = model.conversations.showingArchived
			result.effects.append(.manageConversation(operation))
		case .managementFinished(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			), let pending = model.conversations.pendingManagement,
			pending.context == context,
			model.conversations.pendingManagementArchived == model.conversations.showingArchived
			else
			{
				return
			}
			model.conversations.pendingManagement = nil
			switch observation
			{
			case .failed(let failure):
				model.conversations.error = "Could not change conversation: \(failure.message)"
			case .succeeded:
				model.conversations.error = nil
				switch pending
				{
				case .rename(
					_,
					let name
				):
					if let index = model.preferences.pinnedTasks
						.firstIndex(where:
							{
								$0.id == context.threadID
							})
					{
						model.preferences.pinnedTasks[index].name = name
						persistTaskPin(
							model.preferences.pinnedTasks[index],
							pinned: true,
							context: context,
							model: &model,
							result: &result
						)
					}
				case .archive, .delete:
					if let task = model.preferences.pinnedTasks
						.first(where:
							{
								$0.id == context.threadID
							})
					{
						model.preferences.pinnedTasks.removeAll
						{
							$0.id == task.id
						}
						persistTaskPin(
							task,
							pinned: false,
							context: context,
							model: &model,
							result: &result
						)
					}
					if context.threadID == model.conversations.selectedConversation.threadID
					{
						select(
							.newChat,
							context: context,
							model: &model,
							result: &result,
							acceptedSelection: &acceptedSelection
						)
					}
					if case .delete = pending, let id = context.threadID
					{
						model.conversations.content.removeValue(forKey: .thread(id))
						model.conversations.cacheAccounting.removeThread(threadID: id)
						model.conversations.turnReferenceIndices.removeValue(forKey: id)
						model.conversations.threads.removeAll
						{
							$0.id == id
						}
					}
				case .unarchive:
					model.conversations.showingArchived = false
					select(
						.thread(context.threadID!),
						context: context,
						model: &model,
						result: &result,
						acceptedSelection: &acceptedSelection
					)
					requestHistory(
						ConversationReadOperation(
							context: context,
							commandRevision: model.execution(for: .thread(context.threadID!))
								.commandEventRevisions[
									context.threadID!,
									default: 0
								],
							purpose: .recovery
						),
						model: &model,
						result: &result
					)
				}
				let list = ConversationListOperation(
					context: context,
					archived: model.conversations.showingArchived,
					boundThreadID: model.conversations.boundThreadID
				)
				model.conversations.pendingList = list
				result.effects.append(.readConversationList(list))
			}
		case .selectionPersistenceFinished(
			let context,
			let resultValue
		):
			guard valid(
				context,
				model
			), model.conversations.pendingSelectionPersistence == context
			else
			{
				return
			}
			model.conversations.pendingSelectionPersistence = nil
			if case .failed(let failure) = resultValue
			{
				model.conversations.error = failure.message
			}
		case .selectionReceived, .itemStarted, .itemFinished, .agentMessageDelta,
				.commandOutputDelta, .fileChangesReceived, .aggregateDiffReceived: break
		}
	}

	private static func prependHistoryPage(
		_ page: HistoryPage,
		operation: HistoryLoadOperation,
		liveTurnID: String?,
		threadID: String,
		content: inout ConversationProjection
	)
	{
		let liveEntryPrefix = liveTurnID.map
		{
			$0 + ":"
		}
		let streamedEntries = content.entries.filter
		{
			entry in
			liveEntryPrefix.map(entry.id.hasPrefix) == true
		}

		var knownTurnIDs = Set(content.loadedTurns.map(\.id))
		let earlier = page.turns.filter
		{
			knownTurnIDs.insert($0.id).inserted
		}
		content.loadedTurns.insert(
			contentsOf: earlier,
			at: 0
		)
		content.hasLoadedHistory = true
		content.nextTurnsCursor = page.nextCursor == operation.pageScope
			.cursor ? nil : page.nextCursor
		content.entries = ConversationContentReducer.entries(for: content.loadedTurns)
		for entry in streamedEntries
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

	private static func persistTaskPin(
		_ task: ThreadSummary,
		pinned: Bool,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let write = PreferenceWrite(
			context: context,
			value: .taskPin(
				task,
				pinned: pinned
			)
		)
		model.preferences.pendingPreferenceWrites[write.key] = context
		model.preferences.preferenceWriteErrors.removeValue(forKey: write.key)
		result.effects.append(.persistPreference(write))
	}

	/// Composes accepted feature transitions into canonical conversation content.
	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch event
		{
		case .connectionBegan, .connectionDisconnected:
			model.conversations.observedThreadNames.removeAll()
			model.conversations.pendingReads.removeAll()
			model.conversations.historyLoads.removeAll()
			model.conversations.pendingTurnReads.removeAll()
			for threadID in model.conversations.turnReferenceIndices.keys
			{
				model.conversations.turnReferenceIndices[threadID]?.pendingRead = nil
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewRead = nil
				model.conversations.turnReferenceIndices[threadID]?.pendingPreviewPromotion = nil
				model.conversations.turnReferenceIndices[threadID]?.pendingWindowRead = nil
				model.conversations.turnReferenceIndices[threadID]?.windowQueue.removeAll()
				model.conversations.turnReferenceIndices[threadID]?.hasLoadedPage = false
			}
			model.conversations.pendingList = nil
			model.conversations.pendingSelection = nil
			model.conversations.pendingManagement = nil
			model.conversations.pendingProjectArchive = nil
		case .conversationSelectionChanged:
			ensureTurnReferences(
				model: &model,
				result: &result
			)
		case .submissionAccepted(let submission):
			if let threadID = submission.context.threadID
			{
				model.conversations.contentRevisions[threadID, default: 0] += 1
			}
			ConversationContentReducer.updateConversation(
				submission.conversation,
				model: &model
			)
			{
				content in
				ConversationContentReducer.resetChanges(&content)
				let localID = "local:\(submission.context.requestID)"
				if let turnID = submission.context.turnID
				{
					content.content.localUserMessageTurnIDs[localID] = turnID
				}
				content.entries.append(ConversationEntry(
					id: localID,
					kind: .user,
					title: "You",
					body: UserMessagePresenter.body(for: submission.inputs),
					imageAttachments: UserMessagePresenter.imageAttachments(for: submission.inputs),
					sourceReferences: UserMessagePresenter.sourceReferences(for: submission.inputs)
				))
			}
		case .completedHistoryReadRequested(let operation):
			requestHistory(
				operation,
				model: &model,
				result: &result
			)
		case .submissionPrepared(let prepared):
			model.conversations.contentRevisions[prepared.thread.summary.id, default: 0] += 1
			if prepared.submission.context.threadID == nil
			{
				let key = ConversationKey.thread(prepared.thread.summary.id)
				let lifetime = prepared.submission.draft.lifetime
				if let content = model.conversations.pendingNewChatContent
					.removeValue(forKey: lifetime)
				{
					model.conversations.content[key] = content
				}
				else if model.conversations.content[key] == nil
				{
					let localID = "local:\(prepared.submission.context.requestID)"
					var source = model.conversations.content[.newChat] ?? ConversationContentModel()
					var transferred = ConversationContentModel()
					transferred.entries = source.entries.filter
					{
						$0.id == localID
					}
					source.entries.removeAll
					{
						$0.id == localID
					}
					model.conversations.content[key] = transferred
					model.conversations.content[.newChat] = source
				}
				model.conversations.threads.removeAll
				{
					$0.id == prepared.thread.summary.id
				}
				var summary = prepared.thread.summary
				if summary.preview?.isEmpty != false
				{
					summary.preview = ThreadTitleText.normalized(prepared.submission.draft.text)
				}
				model.conversations.threads.insert(
					summary,
					at: 0
				)
				if model.conversations.selectedConversation == key
				{
					model.conversations.selectedConversation = key

					var context = prepared.submission.context
					context.threadID = prepared.thread.summary.id
					model.conversations.pendingSelectionPersistence = context
					result.effects.append(.persistConversationSelection(
						context,
						threadID: prepared.thread.summary.id
					))
				}
			}
			if let workspace = prepared.workspace
			{
				model.conversations.boundThreadID = workspace.threadID
			}
		case .backendObserved(
			let event,
			let observedAt
		):
			switch event
			{
			case .threadNameUpdated(
				let threadID,
				let name
			):
				model.conversations.observedThreadNames.updateValue(
					name,
					forKey: threadID
				)
				if let index = model.conversations.threads.firstIndex(where:
					{
						$0.id == threadID
					})
				{
					model.conversations.threads[index].name = name
				}
			case .turnStarted(
				let threadID,
				_
			), .turnCompleted(
				let threadID,
				_
			), .itemStarted(
				let threadID,
				_,
				_
			), .itemCompleted(
				let threadID,
				_,
				_
			), .agentMessageDelta(
				let threadID,
				_,
				_,
				_
			), .commandOutputDelta(
				let threadID,
				_,
				_,
				_
			), .fileChangeUpdated(
				let threadID,
				_,
				_,
				_
			), .diffUpdated(
				let threadID,
				_,
				_
			):
				model.conversations.contentRevisions[threadID, default: 0] += 1
			default: break
			}
			if let identity = event.turnContentIdentity
			{
				invalidateCachedTurn(
					identity.turnID,
					threadID: identity.threadID,
					model: &model
				)
			}
			ConversationContentReducer.observe(
				event,
				model: &model,
				observedAt: observedAt
			)
		case .historyAccepted(
			let detail,
			_
		):
			model.conversations.contentRevisions[detail.summary.id, default: 0] += 1
			ConversationContentReducer.merge(
				detail,
				model: &model
			)
			ensureTurnReferences(
				model: &model,
				result: &result
			)
		default: break
		}
		switch event
		{
		case .backendObserved(
			let backendEvent,
			_
		):
			if let identity = backendEvent.turnContentIdentity
			{
				enforceCacheLimits(
					model: &model,
					updating: [identity.threadID],
					includePreviews: false
				)
			}
		case .submissionAccepted(let submission):
			if let threadID = submission.context.threadID
			{
				enforceCacheLimits(
					model: &model,
					updating: [threadID],
					includePreviews: false
				)
			}
		case .submissionPrepared(let prepared):
			enforceCacheLimits(
				model: &model,
				updating: [prepared.thread.summary.id]
			)
		case .historyAccepted(
			let detail,
			_
		):
			enforceCacheLimits(
				model: &model,
				updating: [detail.summary.id]
			)
		case .conversationContentChanged, .conversationSelectionChanged,
				.connectionBegan, .connectionDisconnected:
			enforceCacheLimits(model: &model)
		default: break
		}
		return result
	}
}

extension ThreadManagementOperation
{
	var context: OperationContext
	{
		switch self
		{
		case .rename(
			let context,
			_
		), .archive(let context), .unarchive(let context), .delete(let context): return context
		}
	}
}
