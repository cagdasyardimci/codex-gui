import Foundation

/// Keeps cross-feature workflows synchronous at their original reducer positions.
@MainActor
enum WorkspaceFeatureComposition
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		result.merge(
			reduceExecution(
				&model,
				action
			)
		)
		result.merge(
			ComposerReducer.reduce(
				&model,
				action
			)
		)
		result.merge(
			reduceConversation(
				&model,
				action
			)
		)
		result.merge(
			ReviewReducer.reduce(
				&model,
				action
			)
		)
		result.merge(
			reduceNavigation(
				&model,
				action
			)
		)
		return result
	}

	static func reduceExecution(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = ExecutionReducer.reduce(
			&model,
			action
		)
		if case .execution(let executionAction) = action
		{
			reduceExecutionHistoryRequest(
				executionAction,
				model: &model,
				result: &result
			)
		}
		return result
	}

	/// Also serves nested command and startup selections that already reduce in place.
	static func reduceConversation(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction,
		reduceSelectionExecution: @MainActor (
			inout WorkspaceModel,
			ExecutionAction
		)
			-> WorkspaceReduction =
			{
				model, selection in
				ExecutionReducer.reduce(
					&model,
					.execution(selection)
				)
			}
	) -> WorkspaceReduction
	{
		var (conversation, acceptedHistory, acceptedSelection) =
			ConversationReducer.reduceForComposition(
				&model,
				action
			)
		if let acceptedSelection
		{
			composeAcceptedSelection(
				acceptedSelection,
				model: &model,
				conversation: &conversation,
				reduceSelectionExecution: reduceSelectionExecution
			)
		}
		var result = conversation
		if let acceptedHistory
		{
			composeAcceptedHistory(
				acceptedHistory,
				model: &model,
				result: &result
			)
		}
		return result
	}

	private static func composeAcceptedSelection(
		_ acceptedSelection: ConversationReducer.AcceptedSelection,
		model: inout WorkspaceModel,
		conversation: inout WorkspaceReduction,
		reduceSelectionExecution: @MainActor (
			inout WorkspaceModel,
			ExecutionAction
		) -> WorkspaceReduction
	)
	{
		let execution = reduceSelectionExecution(
			&model,
			acceptedSelection.executionAction
		)
		conversation.effects.insert(
			contentsOf: execution.effects,
			at: acceptedSelection.effectIndex
		)
		conversation.domainEvents.insert(
			contentsOf: execution.domainEvents,
			at: acceptedSelection.domainEventIndex
		)
		conversation.presentationCommands.insert(
			contentsOf: execution.presentationCommands,
			at: acceptedSelection.presentationCommandIndex
		)
	}

	private static func composeAcceptedHistory(
		_ acceptedHistory: ConversationReducer.AcceptedHistory,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		// Preserve the original effects, then composer events, then execution events.
		let executionAction = WorkspaceAction.execution(acceptedHistory.executionAction)
		let execution = ExecutionReducer.reduce(
			&model,
			executionAction
		)
		let composer = ComposerReducer.reduce(
			&model,
			executionAction
		)
		result.effects.append(contentsOf: execution.effects)
		result.effects.append(contentsOf: composer.effects)
		result.domainEvents.append(contentsOf: composer.domainEvents)
		result.presentationCommands.append(contentsOf: composer.presentationCommands)
		result.domainEvents.append(contentsOf: execution.domainEvents)
		result.presentationCommands.append(contentsOf: execution.presentationCommands)
		ConversationReducer.finishAcceptedHistory(
			acceptedHistory,
			model: &model,
			result: &result
		)
	}

	static func reduceNavigation(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = ContextNavigationReducer.reduce(
			&model,
			action
		)
		if case .contextNavigation(.savedPromptInserted(
			let context,
			let promptID
		)) = action,
			let draftAction = ContextNavigationReducer.savedPromptDraftAction(
				context: context,
				promptID: promptID,
				model: model
			)
		{
			result.merge(
				ComposerReducer.reduce(
					&model,
					draftAction
				)
			)
		}
		return result
	}

	private static func reduceExecutionHistoryRequest(
		_ action: ExecutionAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let operation: ReconciliationOperation
		let purpose: ConversationReadPurpose
		switch action
		{
		case .reconciliationRequested(let requested):
			guard model.execution.pendingReconciliation == requested
			else
			{
				return
			}
			operation = requested
			purpose = .recovery
		case .completedHistoryRequested(let requested):
			guard ExecutionReducer.valid(
				requested.context,
				model
			)
			else
			{
				return
			}
			operation = requested
			purpose = .completion
		default: return
		}
		result.merge(
			ConversationReducer.reduce(
				&model,
				.conversations(.historyRequested(ConversationReadOperation(
					context: operation.context,
					commandRevision: operation.commandRevision,
					purpose: purpose
				)))
			)
		)
	}
}
