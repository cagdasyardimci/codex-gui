import Foundation

/// Execution ownership survives navigation and is independent of command exit evidence.
@MainActor
enum ExecutionReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)
	static let uncertainResponseWarningPrefix = "Response delivery is uncertain. "

	static func reduce(
		_ model: inout WorkspaceModel,
		_ workspaceAction: WorkspaceAction
	) -> WorkspaceReduction
	{
		guard WorkspaceExecutionScope.canResolve(
			action: workspaceAction,
			model: model
		)
		else
		{
			return WorkspaceReduction()
		}
		return WorkspaceExecutionScope.reduce(
			action: workspaceAction,
			model: &model,
			body:
			{
				model in reduceCanonical(
					&model,
					workspaceAction
				)
			}
		)
	}

	private static func reduceCanonical(
		_ model: inout WorkspaceModel,
		_ workspaceAction: WorkspaceAction
	) -> WorkspaceReduction
	{
		guard case .execution(let action) = workspaceAction
		else
		{
			return WorkspaceReduction()
		}
		var result = WorkspaceReduction()
		switch action
		{
		case .conversationSelected(
			let threadID,
			let recovering
		):
			if !model.execution.state.isBusy && model.execution.activeThreadID != threadID
			{
				model.execution.statusMessage = nil
			}
			if model.execution.activeThreadID == nil && !model.execution.state.isBusy
			{
				model.execution.needsReconciliation = recovering
			}
		case .conversationCleared:
			if !model.execution.state.isBusy && model.execution.activeThreadID == nil
			{
				model.execution.needsReconciliation = false
				model.execution.hasUncertainRequest = false
				model.execution.state = model.connection.isConnected ? .ready : .disconnected
				model.execution.statusMessage = nil
			}
		case .recoveryTargetUnavailable:
			model.execution.state = .failed
			model.execution.statusMessage =
				"Inspect recent conversations, then choose one or start a new "
					+ "chat. The previous request was not resent."
		case .submissionRequested(let submission):
			guard WorkspaceEligibility(model: model).acceptsSubmission(submission)
			else
			{
				return result
			}
			model.execution.owner = ExecutionOwner(submission: submission.context)
			if let pending = model.execution.pendingGitTurnBaselineCapture
			{
				result.effects.append(.discardGitTurnBaseline(GitTurnBaselineDiscardOperation(
					context: submission.context,
					reference: pending.reference
				)))
				model.execution.pendingGitTurnBaselineCapture = nil
			}
			model.execution.agentOutcome = nil
			model.execution.submissionRequest = submission.context
			model.execution.activeThreadID = submission.context.threadID
			model.execution.activeTurnID = nil
			model.execution.outcomeMessage = nil
			model.execution.deferredTurnOutcome = nil
			model.execution.deferredTurnMessage = nil
			model.execution.reconcilingCommandOutcome = false
			model.execution.state = .running
			model.execution.statusMessage = "Sending request…"
			model.execution.stopRequested = false
			model.execution.interruptRequestSent = false
			model.execution.activePlan = nil
			model.execution.activeActivity = nil
			result.effects.append(.prepareSubmission(submission))
			result.domainEvents = [.submissionAccepted(submission)]
		case .submissionPrepared(
			let context,
			let observation
		):
			guard owns(
				context,
				model
			)
			else
			{
				return result
			}
			switch observation
			{
			case .failed(let failure):
				failSubmission(
					failure,
					model: &model,
					result: &result
				)
			case .succeeded(let prepared):
				guard model.adoptExecution(
					for: context,
					threadID: prepared.thread.summary.id
				)
				else
				{
					model.execution.needsReconciliation = true
					model.execution.hasUncertainRequest = true
					model.execution.state = .failed
					model.execution.statusMessage =
						"Codex assigned a conversation that already has a running request. "
							+ "Refresh both conversations before sending again."
					return result
				}
				model.execution.activeThreadID = prepared.thread.summary.id
				model.execution.owner?.submission.threadID = prepared.thread.summary.id
			}
		case .preparedPersistenceFinished(
			let context,
			let observation
		):
			guard owns(
				context,
				model
			)
			else
			{
				return result
			}
			switch observation
			{
			case .failed(let failure): failSubmission(
					failure,
					model: &model,
					result: &result
				)
			case .succeeded(let prepared):
				if model.execution.stopRequested
				{
					model.execution.state = .completed
					model.execution.statusMessage = "Request canceled before the task started."
					model.execution.submissionRequest = nil
					model.execution.stopRequested = false
					result.presentationCommands = [.taskFinished]
				}
				else
				{
					result.effects = [.startSubmission(prepared)]
				}
			}
		case .submissionAcknowledged(
			let context,
			let acknowledgement
		):
			guard owns(
				context,
				model
			)
			else
			{
				return result
			}
			model.execution.submissionRequest = nil
			let reportedTurnID = model.execution.activeTurnID
				?? model.execution.owner?.submission.turnID
			if let eventTurnID = reportedTurnID,
				eventTurnID != acknowledgement.turn.id
			{
				model.execution.needsReconciliation = true
				model.execution.hasUncertainRequest = true
				model.execution.state = .failed
				model.execution.statusMessage =
					"Codex reported a different turn. Refresh the conversation before "
						+ "sending again."
				return result
			}
			GitTurnBaselineLifecycle.acknowledge(
				acknowledgement,
				context: context,
				model: &model,
				result: &result
			)
			if model.execution.state == .running || model.execution.state == .stopping
			{
				model.execution.activeTurnID = acknowledgement.turn.id
				model.execution.owner?.submission.turnID = acknowledgement.turn.id
				requestInterruption(
					model: &model,
					result: &result
				)
			}
			if model.conversations.selectedConversation.threadID == acknowledgement.thread
				.id && model.execution
				.state.isBusy
			{
				model.execution.statusMessage = nil
			}
		case .submissionCancelledBeforeSend(let context):
			guard owns(
				context,
				model
			), model.execution.stopRequested,
			model.execution.submissionRequest?.isSameRequest(as: context) == true
			else
			{
				return result
			}
			model.execution.submissionRequest = nil
			model.execution.stopRequested = false
			model.execution.stopContext = nil
			model.execution.state = .completed
			model.execution.statusMessage = "Request canceled before the task started."
			result.presentationCommands = [.taskFinished]
		case .submissionStartFailed(
			let context,
			let failure,
			let pending
		):
			guard owns(
				context,
				model
			)
			else
			{
				return result
			}
			if failure.outcomeIsUncertain
			{
				model.execution.pendingGitTurnBaselineCapture = pending
			}
			failSubmission(
				failure,
				model: &model,
				result: &result
			)
		case .gitTurnBaselineBindingFinished(
			let context,
			let threadID,
			let turnID,
			let observation
		):
			GitTurnBaselineLifecycle.finishBinding(
				observation,
				context: context,
				threadID: threadID,
				turnID: turnID,
				model: &model
			)
		case .gitTurnBaselineDiscarded: break
		case .submissionFailed(
			let context,
			let failure
		):
			guard owns(
				context,
				model
			)
			else
			{
				return result
			}
			failSubmission(
				failure,
				model: &model,
				result: &result
			)
		case .stopRequested(
			let context,
			_
		):
			guard model.execution.agentOutcome == nil,
					context.threadID == nil || context.threadID == model.execution.activeThreadID,
					context.turnID == nil || context.turnID == model.execution.activeTurnID,
					valid(
					context,
					model
					),
					[.running, .awaitingApproval, .awaitingAnswer].contains(model.execution.state)
			else
			{
				return result
			}
			model.execution.state = .stopping
			model.execution.statusMessage =
				"Stop requested. Waiting for Codex to confirm the outcome…"
			model.execution.stopRequested = true
			if model.execution.stopContext != context
			{
				model.execution.interruptRequestSent = false
				model.execution.pendingInterruption = nil
			}
			model.execution.stopContext = context
			requestInterruption(
				model: &model,
				result: &result
			)
		case .interruptionFinished(
			let context,
			let observation
		):
			guard model.execution.pendingInterruption?.context == context,
					valid(
					context,
					model
					), model.execution.activeThreadID == context.threadID,
					model.execution.activeTurnID == context.turnID, model.execution.stopRequested
			else
			{
				return result
			}
			model.execution.pendingInterruption = nil
			if case .failed(let failure) = observation
			{
				model.execution.statusMessage = "Could not request a stop: \(failure.message)"
				model.execution.needsReconciliation = true
				if model.execution.state != .disconnected
				{
					model.execution.state = .failed
				}
			}
		case .steeringRequested(let operation):
			guard WorkspaceEligibility(model: model).acceptsSteering(operation)
			else
			{
				return result
			}
			model.execution.pendingSteering = operation.context
			result.effects = [.steer(operation)]
		case .steeringFinished(
			let context,
			let observation
		):
			guard model.execution.pendingSteering == context,
					let submission = model.composer.pendingSubmissions[context.requestID]
			else
			{
				return result
			}
			return reduce(
				&model,
				.execution(.steeringTransportFinished(
					SteeringOperation(
						context: context,
						submission: submission
					),
					observation
				))
			)
		case .steeringTransportFinished(
			let operation,
			let observation
		):
			let context = operation.context
			if model.execution.pendingSteering == context
			{
				model.execution.pendingSteering = nil
			}
			guard valid(
				context,
				model
			), model.execution.activeThreadID == context.threadID,
			model.execution.activeTurnID == context.turnID
			else
			{
				return result
			}
			switch observation
			{
			case .succeeded(let turnID):
				if turnID != context.turnID
				{
					model.execution.needsReconciliation = true
					model.execution.hasUncertainRequest = true
					model.execution.statusMessage = "Codex acknowledged a different turn. "
						+ "Refresh the "
						+ "conversation before sending another instruction."
				}
				else if model.execution.state.isBusy
				{
					model.execution.statusMessage = "Instruction added to the running task."
				}
			case .failed(let failure):
				model.execution.needsReconciliation = true
				model.execution.hasUncertainRequest = true
				model.execution.statusMessage =
					"Instruction outcome is uncertain. "
						+ "Refresh this "
						+ "conversation after the task finishes. \(failure.message)"
			}

		case .interactionResponseRequested(let operation):
			guard valid(
				operation.context,
				model
			), model.connection.isConnected,
			model.execution.agentOutcome == nil,
			model.execution.activeThreadID == operation.context.threadID,
			model.execution.activeTurnID == operation.context.turnID,
			model.execution.pendingResponses[operation.interactionID] == nil,
			model.execution.pendingInteractions.contains(where:
				{
					$0.id == operation.interactionID
				})
			else
			{
				return result
			}
			model.execution.pendingResponses[operation.interactionID] = operation
			result.effects = [.respond(operation)]
		case .interactionResponseFinished(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			),
				let operation = model.execution.pendingResponses.values.first(where:
					{
						$0.context == context
					})
			else
			{
				return result
			}
			guard model.execution.activeThreadID == context.threadID,
					model.execution.activeTurnID == context.turnID
			else
			{
				model.execution.pendingResponses.removeValue(forKey: operation.interactionID)
				return result
			}
			switch observation
			{
			case .succeeded:
				model.execution.pendingResponses.removeValue(forKey: operation.interactionID)
				model.execution.pendingInteractions.removeAll
				{
					$0.id == operation.interactionID
				}
				updateAwaitingState(&model.execution)
				model.execution.statusMessage = nil
			case .failed(let failure):
				if failure.outcomeIsUncertain
				{
					// The transport still reserves a possibly sent response; do not admit a retry.
					model.execution.statusMessage = uncertainResponseWarningPrefix
						+ "Wait for Codex to resolve this request before retrying. "
						+ failure.message
				}
				else
				{
					model.execution.pendingResponses.removeValue(forKey: operation.interactionID)
					model.execution.statusMessage = "Could not submit response: \(failure.message)"
				}
			}
		case .reconciliationRequested, .reconciliationFinished, .historyObserved,
				.completedHistoryRequested, .completedHistoryReceived:
			return reduceReconciliation(
				action,
				model: &model
			)
		case .backendObserved(
			_,
			let event,
			_
		):
			guard ComposerCommandReducer.acceptsExecutionEvent(
				event,
				model: model
			)
			else
			{
				return result
			}
			return reduceObservation(
				action,
				model: &model
			)
		default: break
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

	private static func owns(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		valid(
			context,
			model
		) && model.execution.owner?.submission.isSameRequest(as: context) == true
			&& (context.threadID == nil || context.threadID == model.execution.activeThreadID)
			&& (context.turnID == nil
				|| context.turnID == model.execution.activeTurnID
				|| context.turnID == model.execution.owner?.submission.turnID)
	}

	static func requestInterruption(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard model.execution.stopRequested, !model.execution.interruptRequestSent,
				let threadID = model.execution.activeThreadID,
				let turnID = model.execution.activeTurnID,
				var context = model.execution.stopContext,
				valid(
				context,
				model
				)
		else
		{
			return
		}
		context.threadID = threadID
		context.turnID = turnID
		model.execution.interruptRequestSent = true
		let operation = InterruptionOperation(context: context)
		model.execution.pendingInterruption = operation
		result.effects.append(.interrupt(operation))
	}

	private static func failSubmission(
		_ failure: OperationFailure,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		model.execution.submissionRequest = nil
		model.execution.needsReconciliation = failure.outcomeIsUncertain
		model.execution.hasUncertainRequest = failure.outcomeIsUncertain
		model.execution.state = model.connection.isConnected ? .failed : .disconnected
		if failure.outcomeIsUncertain
		{
			model.execution.statusMessage =
				"Request outcome is uncertain. Reopen this conversation before "
					+ "trying again. \(failure.message)"
		}
		else
		{
			model.execution.stopRequested = false
			model.execution.stopContext = nil
			model.execution.statusMessage = "Could not start the task: \(failure.message)"
			result.presentationCommands.append(.taskFinished)
		}

	}

	static func updateAwaitingState(_ execution: inout ExecutionModel)
	{
		guard [.running, .awaitingApproval, .awaitingAnswer].contains(execution.state)
		else
		{
			return
		}
		let hasPendingQuestion = execution.pendingInteractions.contains
		{
			if case .question = $0.kind
			{
				return true
			}
			return false
		}

		if hasPendingQuestion
		{
			execution.state = .awaitingAnswer
		}
		else
		{
			execution.state = execution.pendingInteractions.isEmpty ? .running : .awaitingApproval
		}
	}

	static func finishDeferred(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard !model.execution.commandLifetime.hasPendingCommands,
				let outcome = model.execution.deferredTurnOutcome
		else
		{
			return
		}
		model.execution.deferredTurnOutcome = nil
		if model.execution.reconcilingCommandOutcome
		{
			model.execution.needsReconciliation = false
			model.execution.hasUncertainRequest = false
			model.execution.reconcilingCommandOutcome = false
		}
		model.execution.state = outcome
		model.execution.statusMessage = model.execution.deferredTurnMessage
		model.execution.outcomeMessage = model.execution.statusMessage
		model.execution.deferredTurnMessage = nil
		result.presentationCommands.append(.taskFinished)
	}

}
