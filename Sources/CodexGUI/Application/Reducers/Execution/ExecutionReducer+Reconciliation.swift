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

		case .reconciliationFinished(
			let context,
			let observation
		):
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
				invalidateReconciliationToken(
					for: context,
					model: &model
				)
				return result
			}

			switch observation
			{
			case .succeeded(let detail):
				guard detail.summary.id == threadID
				else
				{
					return result
				}
				reconcile(
					detail,
					context: context,
					model: &model,
					result: &result
				)
			case .failed(let failure):
				invalidateReconciliationToken(
					for: context,
					model: &model
				)
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
			guard valid(
				operation.context,
				model
			), let threadID = operation.context.threadID, detail.summary.id == threadID
			else
			{
				return result
			}
			guard model.execution.commandEventRevisions[threadID, default: 0]
				== operation.commandRevision
			else
			{
				invalidateReconciliationToken(
					for: operation.context,
					model: &model
				)
				return result
			}
			if detail.isReadOnlyDueToActiveWriter
			{
				// Display saved history without adopting the other process's turn.
				result.domainEvents = [.historyAccepted(
					detail,
					threadID: threadID
				)]
				return result
			}
			// An uncertain steering request does not revoke a live turn's execution ownership.
			let preservesLiveTurn = model.execution.activeTurnID != nil
				&& model.execution.agentOutcome == nil
				&& (!model.execution.needsReconciliation || model.execution.state.isBusy)
			let shouldPreserveExecutionOwner = operation.contentOnly
				|| model.execution.activeThreadID != nil
				&& (model.execution.activeThreadID != detail.summary.id || preservesLiveTurn)

			if shouldPreserveExecutionOwner
			{
				let commandPersistenceEffect = reconcileCommands(
					threadID: detail.summary.id,
					turns: detail.turns,
					context: operation.context,
					model: &model
				)
				result.effects.append(commandPersistenceEffect)
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
			// Mint only after this accepted history has incorporated its command evidence.
			model.execution.lastReconciledRequestID = operation.context.requestID
		case .completedHistoryRequested(let operation):
			guard valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
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
			if case .succeeded(let detail) = observation
			{
				guard detail.summary.id == operation.context.threadID
				else
				{
					return result
				}
				let commandPersistenceEffect = reconcileCommands(
					threadID: detail.summary.id,
					turns: detail.turns,
					context: operation.context,
					model: &model
				)
				result.effects = [commandPersistenceEffect]
				result.domainEvents.append(.historyAccepted(
					detail,
					threadID: detail.summary.id
				))
				finishDeferred(
					model: &model,
					result: &result
				)
			}
			result.domainEvents.append(.completedHistoryRefreshed)
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
		let containsCommandExecution = turns.contains
		{
			$0.items.contains
			{
				$0.type == "commandExecution"
			}
		}
		if containsCommandExecution
		{
			recordCommandEvent(
				threadID: threadID,
				model: &model
			)
		}
	}

	static func recordCommandEvent(
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		var execution = model.execution(for: .thread(threadID))
		execution.commandEventRevisions[threadID, default: 0] += 1
		execution.lastReconciledRequestID = nil
		model.executions.entries[.thread(threadID)] = execution
	}

	private static func invalidateReconciliationToken(
		for context: OperationContext,
		model: inout WorkspaceModel
	)
	{
		if model.execution.lastReconciledRequestID == context.requestID
		{
			model.execution.lastReconciledRequestID = nil
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
		GitTurnBaselineLifecycle.resolvePendingCapture(
			detail,
			model: &model,
			result: &result
		)
		let isRecoveringExecutionOwner = model.execution.needsReconciliation
			&& model.execution.activeThreadID == threadID
		recoverRunningTurnOwner(
			detail,
			context: context,
			model: &model,
			result: &result
		)

		let commandPersistenceEffect = reconcileCommands(
			threadID: threadID,
			turns: detail.turns,
			context: context,
			model: &model
		)
		result.effects.append(commandPersistenceEffect)
		result.domainEvents.append(.historyAccepted(
			detail,
			threadID: threadID
		))
		let hasLiveTurn = detail.summary.status == "active"
			&& detail.turns.last.map
			{
				ConversationTurnStatus.isRunning($0.status)
			} == true
		if hasLiveTurn
		{
			model.execution.activeThreadID = threadID
			model.execution.needsReconciliation = false
			model.execution.hasUncertainRequest = false
			model.execution.deferredTurnOutcome = nil
			model.execution.deferredTurnMessage = nil
			model.execution.reconcilingCommandOutcome = false
			model.execution.state = .running
			model.execution.statusMessage =
				"Reconnected to the running task. The original request was not resent."
		}
		else if model.execution.commandLifetime.hasPendingCommands
		{
			model.execution.activeThreadID = threadID
			if let turn = detail.turns.first(where:
				{
					model.execution.commandLifetime.owns(
						threadID: threadID,
						turnID: $0.id
					) && !ConversationTurnStatus.isRunning($0.status)
				})
			{
				switch ConversationTurnStatus.lifecycle(turn.status)
				{
				case .interrupted: model.execution.deferredTurnOutcome = .stopped
				case .failed: model.execution.deferredTurnOutcome = .failed
				default: model.execution.deferredTurnOutcome = .completed
				}
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
				ConversationTurnStatus.isRunning(turn.status)
		{
			model.execution.activeThreadID = threadID
			model.execution.needsReconciliation = true
			model.execution.state = .failed
			model.execution.statusMessage =
				"The latest task is still marked as running. Refresh this "
					+ "conversation before sending another request."
		}
		else if model.execution.pendingGitTurnBaselineCapture != nil
		{
			model.execution.needsReconciliation = true
			model.execution.hasUncertainRequest = true
			model.execution.state = .failed
			model.execution.statusMessage =
				"The previous request remains uncertain. Refresh this conversation to check "
					+ "whether a turn began."
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
			if isRecoveringExecutionOwner
			{
				model.execution.activeThreadID = nil
				model.execution.outcomeMessage = nil
			}
		}
		model.execution.lastReconciledRequestID = context.requestID
	}

	static func reconcileCommands(
		threadID: String,
		turns: [CodexTurn],
		context: OperationContext,
		model: inout WorkspaceModel
	) -> WorkspaceEffect
	{
		recordCommandObservation(
			threadID: threadID,
			turns: turns,
			model: &model
		)
		model.execution.commandLifetime.reconcile(
			threadID: threadID,
			turns: turns
		)
		return .persistCommands(
			context,
			model.pendingCommandOwnership
		)
	}

	private static func recoverRunningTurnOwner(
		_ detail: ThreadDetail,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let threadID = detail.summary.id
		if let turn = detail.turns.last,
			ConversationTurnStatus.isRunning(turn.status)
		{
			let currentOwner = model.execution.owner
			let ownerHasCurrentTransport = currentOwner?.submission.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			) == true
			let ownsCurrentTurn = ownerHasCurrentTransport
				&& model.execution.agentOutcome == nil
				&& model.execution.activeThreadID == threadID
				&& model.execution.activeTurnID == turn.id
			let ownsPendingSubmission = currentOwner.map
			{
				owner in
				ownerHasCurrentTransport && model.execution.agentOutcome == nil
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
			requestInterruption(
				model: &model,
				result: &result
			)
		}
	}

}
