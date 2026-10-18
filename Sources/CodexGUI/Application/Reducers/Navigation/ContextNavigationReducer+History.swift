import Foundation

extension ContextNavigationReducer
{
	private static let maximumJumpHistoryPages = 20

	static func reduceHistoryIntent(
		_ action: ContextNavigationAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .searchRequested(
			let context,
			let query
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			model.contextNavigation.pendingSearch = nil
			model.contextNavigation.searchError = nil
			scheduleMessageSearch(
				context,
				query: query,
				model: &model,
				result: &result
			)
		case .searchDismissed(let context):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			cancelMessageSearch(
				model: &model,
				result: &result
			)
			model.contextNavigation.messageSearch = nil
			model.contextNavigation.messageSearchContext = nil
			model.contextNavigation.pendingSearch = nil
			model.contextNavigation.searchError = nil
		case .messageSearchFinished(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			),
				model.contextNavigation.pendingMessageSearch == operation,
				model.contextNavigation.searchIndexRevision == operation.historyRevision,
				model.contextNavigation.messageSearch?.query == operation.query
			else
			{
				return
			}
			model.contextNavigation.pendingMessageSearch = nil
			switch observation
			{
			case .succeeded(let results):
				model.contextNavigation.messageSearch = results
			case .failed(let failure):
				model.contextNavigation.searchError = "Could not search messages: " + failure
					.message
			}
		case .moreSearchHistoryRequested(let context):
			requestMoreSearchHistory(
				context,
				model: &model,
				result: &result
			)
		case .jumpRequested(let operation):
			beginJump(
				operation,
				model: &model,
				result: &result
			)
		case .jumpAcknowledged(let requestID):
			guard model.contextNavigation.pendingJump?.context.requestID == requestID
			else
			{
				return
			}
			model.contextNavigation.pendingJump = nil
			model.contextNavigation.jumpError = nil
		default: break
		}
	}

	private static func requestMoreSearchHistory(
		_ context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			context,
			model
		), model.connection.isConnected,
		model.contextNavigation.pendingSearch == nil,
		model.contextNavigation.messageSearch != nil
		else
		{
			return
		}
		let source = MessageSearchIndexSource(model)
		let searchable = searchableThreads(
			model,
			source: source
		)
		if let missing = model.conversations.threads.first(where:
			{
				source.histories[$0.id] == nil
			})
		{
			var captured = context
			captured.threadID = missing.id
			let operation = ConversationReadOperation(
				context: captured,
				commandRevision: model.execution(for: .thread(missing.id))
					.commandEventRevisions[
						missing.id,
						default: 0
					],
				purpose: .search
			)
			result.merge(
				ConversationReducer
					.reduce(
						&model,
						.conversations(.historyRequested(operation))
					)
			)
			if let pending = model.conversations.pendingReads[operation.key]
			{
				model.contextNavigation.pendingSearch = NavigationSearchOperation(
					context: context,
					read: .history(pending)
				)
			}
		}
		else if let earlier = searchable.first(where: \.hasEarlierTurns),
				let read = requestPage(
					context,
					threadID: earlier.threadID,
					model: &model,
					result: &result
				)
		{
			model.contextNavigation.pendingSearch = NavigationSearchOperation(
				context: context,
				read: read
			)
		}
		model.contextNavigation.searchError = nil
	}

	private static func beginJump(
		_ requested: ConversationJumpOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		var operation = requested
		guard valid(
			operation.context,
			model
		), let threadID = operation.context.threadID,
		model.identity.canonicalCheckoutPath != nil,
		model.conversations.boundThreadID == nil || model.conversations
		.boundThreadID == threadID,
		model.conversations.pendingManagement == nil
		else
		{
			return
		}
		operation.resolvedItemID = operation.itemID.map
		{
			operation.turnID + ":" + $0
		}
		model.contextNavigation.pendingJump = operation
		model.conversations.turnReferenceIndices[threadID]?.navigationProtection = operation.turnID
		model.contextNavigation.jumpError = nil
		if model.conversations.selectedConversation != .thread(threadID)
		{
			result.merge(
				ConversationReducer
					.reduce(
						&model,
						.conversations(.selectionRequested(operation.context))
					)
			)
			if let pending = model.conversations.pendingReads[ConversationReadKey(
				purpose: .selection,
				threadID: threadID
			)]
			{
				model.contextNavigation.pendingJump?.pendingRead = .history(pending)
			}
		}
		if model.contextNavigation.pendingJump?.pendingRead == nil,
			let pending = model.conversations.pendingReads[ConversationReadKey(
			purpose: .selection,
			threadID: threadID
			)]
		{
			model.contextNavigation.pendingJump?.pendingRead = .history(pending)
		}
		resolveJump(
			model: &model,
			result: &result
		)
	}

	private static func searchableThreads(
		_ model: WorkspaceModel,
		source: MessageSearchIndexSource
	) -> [SearchableThread]
	{
		return source.histories.keys.compactMap
		{
			id -> SearchableThread? in
			guard let value = model.conversations.content[.thread(id)],
					let title = source.titles[id]
			else
			{
				return nil
			}
			return SearchableThread(
				threadID: id,
				title: title,
				turns: value.loadedTurns,
				hasEarlierTurns: value.nextTurnsCursor != nil
			)
		}.sorted
		{
			$0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
		}
	}

	private static func requestPage(
		_ context: OperationContext,
		threadID: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	) -> NavigationHistoryRead?
	{
		guard let cursor = model.conversations.content[.thread(threadID)]?.nextTurnsCursor,
				let path = model.identity.canonicalCheckoutPath
		else
		{
			return nil
		}
		if let existing = model.conversations.historyLoads[threadID],
			existing.pageScope.projectPath == path,
			existing.pageScope.generation == model.connection.generation,
			existing.pageScope.cursor == cursor,
			existing.commandRevision == ConversationReducer.commandRevision(
			threadID: threadID,
			model: model
			)
		{
			return .page(existing)
		}
		var captured = context
		captured.threadID = threadID
		let operation = HistoryLoadOperation(
			context: captured,
			pageScope: HistoryPageScope(
				projectPath: path,
				generation: model.connection.generation,
				cursor: cursor
			),
			commandRevision: ConversationReducer.commandRevision(
				threadID: threadID,
				model: model
			)
		)
		result.merge(
			ConversationReducer.reduce(
				&model,
				.conversations(.earlierTurnsRequested(operation))
			)
		)
		return model.conversations.historyLoads[threadID].map(NavigationHistoryRead.page)
	}

	private static func currentRead(
		_ read: NavigationHistoryRead?,
		model: WorkspaceModel
	) -> NavigationHistoryRead?
	{
		guard let read
		else
		{
			return nil
		}
		switch read
		{
		case .history(let operation):
			return model.conversations.pendingReads[operation.key]
				.map(NavigationHistoryRead.history)
		case .page(let operation):
			guard let threadID = operation.context.threadID
			else
			{
				return nil
			}
			return model.conversations.historyLoads[threadID].map(NavigationHistoryRead.page)
		case .turn(let operation):
			guard let threadID = operation.context.threadID
			else
			{
				return nil
			}
			return model.conversations.pendingTurnReads[threadID].map(NavigationHistoryRead.turn)
		}
	}

	static func retargetConsumers(model: inout WorkspaceModel)
	{
		if let search = model.contextNavigation.pendingSearch,
			let read = currentRead(
			search.read,
			model: model
			)
		{
			model.contextNavigation.pendingSearch?.read = read
		}
		if let jump = model.contextNavigation.pendingJump,
			let read = currentRead(
			jump.pendingRead,
			model: model
			)
		{
			model.contextNavigation.pendingJump?.pendingRead = read
		}
	}

	private static func matches(
		_ lhs: NavigationHistoryRead?,
		_ rhs: NavigationHistoryRead
	) -> Bool
	{
		guard let lhs
		else
		{
			return false
		}
		switch (lhs, rhs)
		{
		case (.history(let first), .history(let second)):
			return first.context == second.context
				&& first.purpose == second.purpose
				&& first.commandRevision == second.commandRevision
				&& first.contentRevision == second.contentRevision
		case (.page(let first), .page(let second)):
			return first.context == second.context
				&& first.pageScope == second.pageScope
				&& first.commandRevision == second.commandRevision
		case (.turn(let first), .turn(let second)):
			return first == second
		default: return false
		}
	}

	static func finishRead(
		_ read: NavigationHistoryRead,
		_ observation: OperationResult<Bool>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			read.context,
			model
		)
		else
		{
			return
		}
		let failure = observation.failure
		let applied: Bool
		switch observation
		{
		case .succeeded(let value): applied = value
		case .failed: applied = false
		}
		if let search = model.contextNavigation.pendingSearch, matches(
			search.read,
			read
		)
		{
			model.contextNavigation.pendingSearch = nil
			model.contextNavigation.searchError = failure
				.map
				{
					"Could not load more messages: \($0.message)"
				}
		}
		if let jump = model.contextNavigation.pendingJump, matches(
			jump.pendingRead,
			read
		)
		{
			model.contextNavigation.pendingJump?.pendingRead = nil
			if let failure
			{
				model.contextNavigation
					.jumpError = "Could not load the referenced message: \(failure.message)"
			}
			else if applied,
					case .page = read
			{
				model.contextNavigation.pendingJump?.pagesLoaded += 1
			}
			else if !applied
			{
				model.contextNavigation
					.jumpError = "Conversation history changed. Try the jump again."
			}
		}
	}

	static func resolveJump(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard var jump = model.contextNavigation.pendingJump, valid(
			jump.context,
			model
		),
			let threadID = jump.context.threadID,
			model.conversations.selectedConversation == .thread(threadID),
			let content = model.conversations.content[.thread(threadID)]
		else
		{
			return
		}
		if jump.resolvedItemID == nil
		{
			jump.resolvedItemID = content.entries.first(where:
				{
					$0.id.hasPrefix(jump.turnID + ":") && !$0.id.hasSuffix(":cache-gap")
				})?.id
		}
		model.contextNavigation.pendingJump = jump
		if let itemID = jump.resolvedItemID, content.entries.contains(where:
			{
				$0.id == itemID
			})
		{
			model.contextNavigation.jumpError = nil
			return
		}
		guard jump.pendingRead == nil, model.conversations.pendingSelection == nil,
				content.hasLoadedHistory, model.contextNavigation.jumpError == nil
		else
		{
			return
		}
		if content.loadedTurns.contains(where:
			{
				$0.id == jump.turnID
			})
		{
			model.contextNavigation.jumpError = "The referenced message is unavailable."
			return
		}
		if let reference = model.conversations.turnReferenceIndices[threadID]?.references
			.first(where:
				{
					$0.id == jump.turnID
				})
		{
			let operation = ConversationTurnReadOperation(
				context: jump.context,
				reference: reference,
				commandRevision: ConversationReducer.commandRevision(
					threadID: threadID,
					model: model
				)
			)
			result.merge(
				ConversationReducer
					.reduce(
						&model,
						.conversations(.turnContentsRequested(operation))
					)
			)
			model.contextNavigation.pendingJump?.pendingRead = .turn(operation)
			return
		}
		guard content.nextTurnsCursor != nil
		else
		{
			model.contextNavigation
				.jumpError = "The referenced message is unavailable in this conversation."
			return
		}
		guard jump.pagesLoaded < maximumJumpHistoryPages
		else
		{
			model.contextNavigation.jumpError = "The referenced message is in older history. "
				+ "Load more messages and try again."
			return
		}
		let nextRead = requestPage(
			jump.context,
			threadID: threadID,
			model: &model,
			result: &result
		)
		model.contextNavigation.pendingJump?.pendingRead = nextRead
	}

	private static func updateSearchIndex(model: inout WorkspaceModel) -> Bool
	{
		let source = MessageSearchIndexSource(model)
		guard source != model.contextNavigation.searchIndexSource
		else
		{
			return false
		}
		let threads = searchableThreads(
			model,
			source: source
		)
		model.contextNavigation.searchIndexSource = source
		model.contextNavigation.searchableThreads = threads
		model.contextNavigation.searchIndexRevision += 1
		model.contextNavigation.navigationTargets = ProjectProductivity
			.navigationTargets(threads: threads)
		return true
	}

	static func refreshIndex(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard updateSearchIndex(model: &model),
				let query = model.contextNavigation.messageSearch?.query
		else
		{
			return
		}
		if query.isEmpty
		{
			model.contextNavigation.messageSearch = MessageSearch.pendingResults(
				query: query,
				threads: model.contextNavigation.searchableThreads,
				totalThreadCount: model.contextNavigation.searchIndexSource?.totalThreadCount ?? 0
			)
			return
		}
		guard let context = model.contextNavigation.messageSearchContext
		else
		{
			return
		}
		scheduleMessageSearch(
			context,
			query: query,
			model: &model,
			result: &result
		)
	}

	static func cancelMessageSearch(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		if let operation = model.contextNavigation.pendingMessageSearch
		{
			result.effects.append(.cancelMessageSearch(operation))
		}
		model.contextNavigation.pendingMessageSearch = nil
	}

	static func scheduleMessageSearch(
		_ context: OperationContext,
		query: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		_ = updateSearchIndex(model: &model)
		cancelMessageSearch(
			model: &model,
			result: &result
		)
		let threads = model.contextNavigation.searchableThreads
		let totalThreadCount = model.contextNavigation.searchIndexSource?.totalThreadCount ?? 0
		let pending = MessageSearch.pendingResults(
			query: query,
			threads: threads,
			totalThreadCount: totalThreadCount
		)
		model.contextNavigation.messageSearch = pending
		model.contextNavigation.messageSearchContext = pending.query.isEmpty ? nil : context
		guard !pending.query.isEmpty, !threads.isEmpty
		else
		{
			return
		}
		let operation = MessageSearchOperation(
			context: context,
			query: pending.query,
			historyRevision: model.contextNavigation.searchIndexRevision
		)
		model.contextNavigation.pendingMessageSearch = operation
		result.effects.append(.searchMessages(
			operation,
			threads: threads,
			totalThreadCount: totalThreadCount
		))
	}
}
