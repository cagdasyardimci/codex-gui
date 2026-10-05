import Foundation

/// Project editing and navigation consume the same canonical conversation history.
@MainActor
enum ContextNavigationReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

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
		var result = WorkspaceReduction()
		switch action
		{
		case .connection(.projectOpened(
			let identity,
			_
		)):
			guard identity == model.identity, !model.hasActiveExecution
			else
			{
				return result
			}
			cancelMessageSearch(
				model: &model,
				result: &result
			)
			model.contextNavigation = ContextNavigationModel()
		case .contextNavigation(let intent):
			reduceIntent(
				intent,
				model: &model,
				result: &result
			)
		case .conversations(.historyRequested), .conversations(.earlierTurnsRequested),
				.conversations(.selectionRequested):
			retargetConsumers(model: &model)
		default: break
		}
		return result
	}

	private static func reduceIntent(
		_ action: ContextNavigationAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .contextLoadRequested, .contextReceived, .contextEdited,
				.contextPersistenceFinished, .savedPromptInserted, .bookmarkToggled,
				.skillsRefreshRequested, .skillsInvalidated, .skillsReceived:
			reduceProjectContextIntent(
				action,
				model: &model,
				result: &result
			)
		case .searchRequested, .searchDismissed, .messageSearchFinished,
				.moreSearchHistoryRequested, .jumpRequested, .jumpAcknowledged:
			reduceHistoryIntent(
				action,
				model: &model,
				result: &result
			)
		}
	}

	static func selected(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		(context.threadID.map(ConversationKey.thread) ?? .newChat) == model.conversations
			.selectedConversation
	}

	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch event
		{
		case .connectionBegan, .connectionDisconnected:
			cancelMessageSearch(
				model: &model,
				result: &result
			)
			if let query = model.contextNavigation.messageSearch?.query,
				let previousContext = model.contextNavigation.messageSearchContext
			{
				scheduleMessageSearch(
					OperationContext(
						workspace: model.identity,
						generation: model.connection.generation,
						requestID: previousContext.requestID
					),
					query: query,
					model: &model,
					result: &result
				)
			}
			if let load = model.contextNavigation.pendingContextLoad,
				load.revision == model.contextNavigation.contextRevision
			{
				let context = OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: load.context.requestID
				)
				let refreshed = ContextLoadOperation(
					context: context,
					revision: load.revision
				)
				model.contextNavigation.pendingContextLoad = refreshed
				result.effects.append(.loadProjectContext(refreshed))
			}
			else
			{
				model.contextNavigation.pendingContextLoad = nil
			}
			if let save = model.contextNavigation.pendingContextSave,
				save.revision == model.contextNavigation.contextRevision
			{
				let context = OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: save.context.requestID
				)
				let refreshed = ContextSaveOperation(
					context: context,
					revision: save.revision,
					value: save.value
				)
				model.contextNavigation.pendingContextSave = refreshed
				result.effects.append(.saveProjectContext(refreshed))
			}
			else
			{
				model.contextNavigation.pendingContextSave = nil
			}
			model.contextNavigation.pendingSkillRefresh = nil
			model.contextNavigation.skillRefreshPending = false
			model.contextNavigation.skillCatalog = nil
			model.contextNavigation.skillError = nil
			model.contextNavigation.pendingSearch = nil
			model.contextNavigation.pendingJump = nil
		case .conversationSelectionChanged:
			if let jump = model.contextNavigation.pendingJump, !selected(
				jump.context,
				model
			)
			{
				model.contextNavigation.pendingJump = nil
				model.contextNavigation.jumpError = nil
			}
		case .conversationHistoryFinished(
			let read,
			let observation
		):
			finishRead(
				read,
				observation,
				model: &model,
				result: &result
			)
			refreshIndex(
				model: &model,
				result: &result
			)
			resolveJump(
				model: &model,
				result: &result
			)
		case .historyAccepted, .conversationContentChanged, .backendObserved:
			refreshIndex(
				model: &model,
				result: &result
			)
			resolveJump(
				model: &model,
				result: &result
			)
		default: break
		}
		return result
	}
}

extension OperationResult
{
	var failure: OperationFailure?
	{
		if case .failed(let failure) = self
		{
			return failure
		}

		return nil
	}
}
