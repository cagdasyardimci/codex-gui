import Foundation

/// Draft identity and captured submissions remain independent of the displayed conversation.
@MainActor
enum ComposerReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

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
		var result = WorkspaceReduction()
		observeServerQueues(
			action,
			model: &model
		)
		switch action
		{
		case .conversations(.newChatOpened(let context)):
			guard ConversationReducer.acceptsNewChat(
				context,
				model: model
			)
			else
			{
				return result
			}
			let lifetime = model.composer.drafts[.newChat]?.lifetime
				?? model.composer.pendingNewChatLifetime ?? 0
			ConversationReducer.detachNewChatContent(
				lifetime: lifetime,
				model: &model
			)
			if var draft = model.composer.drafts[.newChat]
			{
				draft.lifetime += 1
				draft.revision += 1
				persist(
					draft,
					conversation: .newChat,
					context: context,
					model: &model,
					result: &result
				)
			}
			else
			{
				model.composer
					.pendingNewChatLifetime = (model.composer.pendingNewChatLifetime ?? 0) + 1
			}
		case .review(.changeRequestPrepared(
			let context,
			let request
		)):
			guard ReviewReducer.accepts(
				context,
				request,
				model: model
			)
			else
			{
				return result
			}
			let conversation = model.conversations.selectedConversation
			let draft = model.composer.drafts[conversation] ?? ComposerDraft()
			let changePrompt = request.reference.prompt(
				for: request.kind,
				file: request.file,
				hunk: request.hunk
			)

			reduceComposer(
				.draftEdited(
					context,
					conversation: conversation,
					text: changePrompt + draft.text,
					revision: draft.revision + 1
				),
				model: &model,
				result: &result
			)
		case .composer(let action):
			reduceComposer(
				action,
				model: &model,
				result: &result
			)
		case .connection(.disconnected(
			let workspace,
			let generation,
			_
		)):
			guard workspace == model.identity, model.connection.generation == generation + 1,
					!model.connection.isConnected
			else
			{
				return result
			}
			model.composer.automaticQueueConversations.removeAll()
			model.composer.uncertainSubmissions.formUnion(model.composer.pendingSubmissions.keys)
			for submission in model.composer.pendingSubmissions.values
			{
				restoreSubmittedDraft(
					submission,
					model: &model,
					result: &result
				)
			}
		case .connection(.projectOpened(
			let identity,
			_
		)):
			guard model.identity == identity, !model.hasActiveExecution
			else
			{
				return result
			}
			if model.composer.workspace != identity
			{
				model.composer = ComposerModel()
			}
			model.composer.workspace = identity

		case .execution(let action):
			reduceExecution(
				action,
				model: &model,
				result: &result
			)
		default: break
		}
		for conversation in model.composer.automaticQueueConversations
		{
			switch model.execution(for: conversation).agentOutcome
			{
			case .stopped, .failed: model.composer.automaticQueueConversations.remove(conversation)
			default: break
			}
		}
		return result
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

	static func clearPersistenceFailure(
		_ key: ComposerPersistenceKey,
		workspace: WorkspaceIdentity,
		model: inout WorkspaceModel
	)
	{
		guard model.composer.persistenceFailure?.key == key,
				model.composer.persistenceFailure?.context.workspace == workspace
		else
		{
			return
		}
		model.composer.persistenceFailure = nil
	}

	static func mergeReferences(
		_ references: [ComposerContextItem],
		conversation: ConversationKey,
		model: inout WorkspaceModel
	)
	{
		var existingReferences = model.composer.sentReferences[conversation] ?? []
		let knownReferenceIDs = Set(existingReferences.map(\.id))
		let newReferences = references.filter
		{
			!knownReferenceIDs.contains($0.id)
		}

		existingReferences.append(contentsOf: newReferences)
		model.composer.sentReferences[conversation] = existingReferences
	}

}
