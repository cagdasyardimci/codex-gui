import Foundation

extension ContextNavigationReducer
{
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
			model.contextNavigation.messageSearch = MessageSearch.search(
				query: query,
				threads: searchableThreads(model),
				totalThreadCount: model
					.conversations.threads
					.count
			)
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
		model.contextNavigation.messageSearch?.scope.canLoadMore == true
		else
		{
			return
		}
		let searchable = searchableThreads(model)
		let cached = Set(searchable.map(\.threadID))
		if let missing = model.conversations.threads.first(where:
			{
				!cached.contains($0.id)
			})
		{
			var captured = context
			captured.threadID = missing.id
			let operation = ConversationReadOperation(
				context: captured,
				commandRevision: model.execution
					.commandEventRevisions[
						missing.id,
						default: 0
					],
				purpose: .search
			)
			append(
				ConversationReducer
					.reduce(
						&model,
						.conversations(.historyRequested(operation))
					),
				to: &result
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
		model.conversations.pendingManagement == nil,
		!(model.execution.state.isBusy && model.execution.activeThreadID == nil)
		else
		{
			return
		}
		operation.resolvedItemID = operation.itemID.map
		{
			operation.turnID + ":" + $0
		}
		model.contextNavigation.pendingJump = operation
		model.contextNavigation.jumpError = nil
		if model.conversations.selectedConversation != .thread(threadID)
		{
			append(
				ConversationReducer
					.reduce(
						&model,
						.conversations(.selectionRequested(operation.context))
					),
				to: &result
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

	static func searchableThreads(_ model: WorkspaceModel) -> [SearchableThread]
	{
		model.conversations.content.compactMap
		{
			key, value -> SearchableThread? in
			guard case .thread(let id) = key, value.hasLoadedHistory
			else
			{
				return nil
			}
			return SearchableThread(
				threadID: id,
				title: model.conversations.threads
					.first(where:
						{
							$0.id == id
						})?.name ?? id,
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
			existing.commandRevision == model.execution.commandEventRevisions[threadID, default: 0]
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
			commandRevision: model.execution.commandEventRevisions[
				threadID,
				default: 0
			]
		)
		append(
			ConversationReducer.reduce(
				&model,
				.conversations(.earlierTurnsRequested(operation))
			),
			to: &result
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
					$0.id.hasPrefix(jump.turnID + ":")
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
		guard content.nextTurnsCursor != nil
		else
		{
			model.contextNavigation
				.jumpError = "The referenced message is unavailable in this conversation."
			return
		}
		guard jump.pagesLoaded < 20
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

	static func refreshIndex(model: inout WorkspaceModel)
	{
		let threads = searchableThreads(model)
		model.contextNavigation.navigationTargets = ProjectProductivity
			.navigationTargets(threads: threads)
		if let query = model.contextNavigation.messageSearch?.query
		{
			model.contextNavigation.messageSearch = MessageSearch.search(
				query: query,
				threads: threads,
				totalThreadCount: model.conversations.threads.count
			)
		}
	}

}
