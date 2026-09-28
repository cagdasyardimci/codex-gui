import Foundation

/// Execution history reads reconcile agent ownership and independent command outcomes.
extension ExecutionReducer
{
	static func reduceReconciliation(
		_ action: ExecutionAction,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .reconciliationRequested(let operation):
			guard valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
			model.execution.pendingReconciliation = operation
			result = ConversationReducer.reduce(
				&model,
				.conversations(.historyRequested(ConversationReadOperation(
					context: operation.context,
					commandRevision: operation.commandRevision,
					purpose: .recovery
				)))
			)

		case .reconciliationFinished(
			let context,
			let observation
		):
			model.execution.lastReconciledRequestID = nil
			guard valid(
				context,
				model
			), let operation = model.execution.pendingReconciliation,
			operation.context == context
			else
			{
				return result
			}
			model.execution.pendingReconciliation = nil
			guard let threadID = context.threadID,
					(model.execution.activeThreadID ?? model.conversations.selectedConversation
					.threadID) == threadID
			else
			{
				return result
			}
			let observedRevision = model.execution.commandEventRevisions[threadID, default: 0]
			guard observedRevision == operation.commandRevision
			else
			{
				return result
			}

			switch observation
			{
			case .succeeded(let detail): reconcile(
					detail,
					context: context,
					model: &model,
					result: &result
				)
			case .failed(let failure):
				model.execution.needsReconciliation = true
				model.execution.state = .failed
				model.execution.statusMessage =
					"Could not check the previous request: \(failure.message). Use "
						+ "Refresh or Reconnect to try again."
			}
		case .historyObserved(
			let operation,
			let detail
		):
			model.execution.lastReconciledRequestID = nil
			guard acceptsHistory(
				operation,
				model
			), detail.summary.id == operation.context.threadID
			else
			{
				return result
			}
			// A scoped accepted read can also retry local reference finalization.
			model.execution.lastReconciledRequestID = operation.context.requestID
			if operation.contentOnly || model.execution
				.activeThreadID != nil &&
				(model.execution.activeThreadID != detail.summary.id || (!model.execution
						.needsReconciliation && model.execution.activeTurnID != nil
						&& model.execution.agentOutcome == nil))
			{
				recordCommandObservation(
					threadID: detail.summary.id,
					turns: detail.turns,
					model: &model
				)
				model.execution.commandLifetime.reconcile(
					threadID: detail.summary.id,
					turns: detail.turns
				)
				result.effects.append(.persistCommands(
					operation.context,
					Array(model.execution.commandLifetime.pending)
				))
				result.domainEvents = [.historyAccepted(
					detail,
					threadID: detail.summary.id
				)]
			}
			else
			{
				reconcile(
					detail,
					context: operation.context,
					model: &model,
					result: &result
				)
			}
		case .completedHistoryRequested(let operation):
			guard valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
			result = ConversationReducer.reduce(
				&model,
				.conversations(.historyRequested(ConversationReadOperation(
					context: operation.context,
					commandRevision: operation.commandRevision,
					purpose: .completion
				)))
			)
		case .completedHistoryReceived(
			let operation,
			let observation
		):
			guard acceptsHistory(
				operation,
				model
			),
				model.execution.activeThreadID != operation.context.threadID || model.execution
				.activeTurnID == nil
			else
			{
				return result
			}
			result.domainEvents.append(.completedHistoryRefreshed)
			if case .succeeded(let detail) = observation
			{
				recordCommandObservation(
					threadID: detail.summary.id,
					turns: detail.turns,
					model: &model
				)
				model.execution.commandLifetime.reconcile(
					threadID: detail.summary.id,
					turns: detail.turns
				)
				result.effects = [.persistCommands(
					operation.context,
					Array(model.execution.commandLifetime.pending)
				)]
				result.domainEvents.append(.historyAccepted(
					detail,
					threadID: detail.summary.id
				))
				finishDeferred(
					model: &model,
					result: &result
				)
			}
		default: break
		}
		return result
	}

	private static func acceptsHistory(
		_ operation: ReconciliationOperation,
		_ model: WorkspaceModel
	) -> Bool
	{
		guard valid(
			operation.context,
			model
		),
			let threadID = operation.context.threadID
		else
		{
			return false
		}
		return model.execution.commandEventRevisions[threadID, default: 0] == operation
			.commandRevision
	}

	static func recordCommandObservation(
		threadID: String,
		turns: [CodexTurn],
		model: inout WorkspaceModel
	)
	{
		if turns.contains(where:
			{
				$0.items.contains
				{
					$0.type == "commandExecution"
				}
			})
		{
			model.execution.commandEventRevisions[threadID, default: 0] += 1
		}
	}

	private static func reconcile(
		_ detail: ThreadDetail,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let threadID = detail.summary.id
		model.execution.lastReconciledRequestID = context.requestID
		let recoveringOwner = model.execution.needsReconciliation && model.execution
			.activeThreadID == threadID
		if let turn = detail.turns.last,
			turn.status == "inProgress" || turn.status == "running"
		{
			let currentOwner = model.execution.owner
			let ownsCurrentTurn = currentOwner != nil
				&& model.execution.agentOutcome == nil
				&& model.execution.activeThreadID == threadID
				&& model.execution.activeTurnID == turn.id
			let ownsPendingSubmission = currentOwner.map
			{
				owner in
				model.execution.agentOutcome == nil
					&& model.execution.submissionRequest?
					.isSameRequest(as: owner.submission) == true
					&& (owner.submission.threadID == nil || owner.submission.threadID == threadID)
					&& (owner.submission.turnID == nil || owner.submission.turnID == turn.id)
			} ?? false
			if !ownsCurrentTurn && !ownsPendingSubmission
			{
				var recovered = context
				recovered.threadID = threadID
				recovered.turnID = turn.id
				model.execution.owner = ExecutionOwner(submission: recovered)
				model.execution.agentOutcome = nil
			}
			model.execution.activeThreadID = threadID
			model.execution.activeTurnID = turn.id
		}
		recordCommandObservation(
			threadID: threadID,
			turns: detail.turns,
			model: &model
		)
		model.execution.commandLifetime.reconcile(
			threadID: threadID,
			turns: detail.turns
		)
		result.effects.append(.persistCommands(
			context,
			Array(model.execution.commandLifetime.pending)
		))
		result.domainEvents.append(.historyAccepted(
			detail,
			threadID: threadID
		))
		if model.execution.commandLifetime.hasPendingCommands
		{
			model.execution.activeThreadID = threadID
			if let turn = detail.turns.first(where:
				{
					model.execution.commandLifetime.owns(
						threadID: threadID,
						turnID: $0.id
					) && $0.status != "inProgress" && $0.status != "running"
				})
			{
				model.execution.deferredTurnOutcome = turn
					.status == "interrupted" ? .stopped :
					(turn.status == "failed" ? .failed : .completed)
				model.execution.deferredTurnMessage =
					"The agent turn finished; approved commands have now reported "
						+ "their outcomes."
				model.execution.reconcilingCommandOutcome = true
			}
			model.execution.needsReconciliation = true
			model.execution.state = .failed
			model.execution.statusMessage =
				"An approved command has no confirmed exit. Refresh this task to "
					+ "check its outcome; its checkout remains protected."
		}
		else if let turn = detail.turns.last,
				turn.status == "inProgress" || turn.status == "running"
		{
			model.execution.activeThreadID = threadID
			model.execution.needsReconciliation = true
			model.execution.state = .failed
			model.execution.statusMessage =
				"The latest task is still marked as running. Refresh this "
					+ "conversation before sending another request."
		}
		else
		{
			model.execution.needsReconciliation = false
			model.execution.deferredTurnOutcome = nil
			model.execution.deferredTurnMessage = nil
			model.execution.reconcilingCommandOutcome = false
			model.execution.state = .ready
			model.execution.statusMessage = model.execution.hasUncertainRequest
				? "Conversation refreshed. Review the saved draft before sending; "
				+ "the request was not resent." : nil
			model.execution.hasUncertainRequest = false
			if recoveringOwner
			{
				model.execution.activeThreadID = nil; model.execution.outcomeMessage = nil
			}
		}
	}

}
