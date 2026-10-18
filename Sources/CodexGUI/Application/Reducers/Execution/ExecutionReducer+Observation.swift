import Foundation

/// Execution backend events retain owner guards and command completion barriers.
extension ExecutionReducer
{
	static func reduceObservation(
		_ action: ExecutionAction,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .backendObserved(
			let context,
			let event,
			let observedAt
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			observe(
				event,
				context: context,
				observedAt: observedAt,
				model: &model,
				result: &result
			)
		default: break
		}
		return result
	}

	private static func acceptsContent(
		threadID: String,
		turnID: String,
		itemID: String? = nil,
		model: WorkspaceModel
	) -> Bool
	{
		if model.execution.commandLifetime.owns(
			threadID: threadID,
			turnID: turnID,
			itemID: itemID
		)
		{
			return true
		}
		if let owner = model.execution.activeThreadID
		{
			return threadID == owner && model.execution.activeTurnID == turnID
		}
		return threadID == model.conversations.selectedConversation.threadID
	}

	private static func observe(
		_ event: AppServerEvent,
		context: OperationContext,
		observedAt: Date?,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let selectedThreadID = model.conversations.selectedConversation.threadID
		switch event
		{
		case .turnStarted(
			let threadID,
			let turn
		):
			guard model.connection.isConnected,
					model.execution.activeThreadID == threadID ||
					(model.execution.activeThreadID == nil && selectedThreadID == threadID),
					model.execution.activeTurnID == nil || model.execution.activeTurnID == turn.id
			else
			{
				return
			}
			let terminalTurnID = model.execution.owner?.submission.turnID
			if model.execution.agentOutcome != nil && terminalTurnID == turn.id
			{
				return
			}
			let startsUnownedTurn = model.execution.owner == nil
				|| model.execution.agentOutcome != nil
			if startsUnownedTurn
			{
				var ownerContext = context
				ownerContext.threadID = threadID
				ownerContext.turnID = turn.id
				model.execution.owner = ExecutionOwner(submission: ownerContext)
				model.execution.agentOutcome = nil
				model.execution.state = .running
			}
			model.execution.activeThreadID = threadID
			model.execution.activeTurnID = turn.id
			model.execution.owner?.submission.threadID = threadID
			model.execution.owner?.submission.turnID = turn.id
			if !model.execution.stopRequested && !model.execution.needsReconciliation
			{
				model.execution.state = .running
				model.execution.statusMessage = nil
			}
			requestInterruption(
				model: &model,
				result: &result
			)
		case .turnCompleted(
			let threadID,
			let turn
		):
			guard model.execution.activeThreadID == threadID ||
				(model.execution.activeThreadID == nil && selectedThreadID == threadID),
				model.execution.activeTurnID == turn.id
			else
			{
				return
			}
			let commandPersistenceEffect = reconcileCommands(
				threadID: threadID,
				turns: [turn],
				context: context,
				model: &model
			)
			result.effects.append(commandPersistenceEffect)
			recordCompletedAgentTurn(
				turn,
				threadID: threadID,
				model: &model
			)
			deferCompletionForPendingCommands(&model)

			model.execution.stopRequested = false
			model.execution.interruptRequestSent = false
			model.execution.pendingInterruption = nil
			model.execution.activePlan = nil
			model.execution.activeActivity = nil
			if !model.execution.commandLifetime.hasPendingCommands
			{
				result.presentationCommands.append(.taskFinished)
			}
			requestCompletedTurnHistory(
				turn,
				threadID: threadID,
				context: context,
				model: model,
				result: &result
			)
		case .itemStarted(
			let threadID,
			let turnID,
			let item
		), .itemCompleted(
			let threadID,
			let turnID,
			let item
		):
			guard acceptsContent(
				threadID: threadID,
				turnID: turnID,
				itemID: item.id,
				model: model
			)
			else
			{
				return
			}
			recordCommandEvent(
				threadID: threadID,
				model: &model
			)
			model.execution.commandLifetime.observe(
				item,
				threadID: threadID,
				turnID: turnID
			)
			result.effects.append(.persistCommands(
				context,
				model.pendingCommandOwnership
			))
			if item.type == "commandExecution"
			{
				model.execution.activeActivity = CommandExecutionStatus.isTerminal(item.status)
					? nil : "Running a command…"
			}
			else if item.type == "mcpToolCall" || item.type == "dynamicToolCall",
					let source = item.sourceActivity
			{
				let finished = ConversationTurnStatus.isTerminal(item.status)
					|| item.status == "declined"
				model.execution.activeActivity = finished
					? nil : "\(source.provider) · \(source.operation)"
			}
			finishDeferred(
				model: &model,
				result: &result
			)
		case .commandOutputDelta(
			let threadID,
			let turnID,
			let itemID,
			_
		):
			guard acceptsContent(
				threadID: threadID,
				turnID: turnID,
				itemID: itemID,
				model: model
			)
			else
			{
				return
			}
			recordCommandEvent(
				threadID: threadID,
				model: &model
			)
		case .agentMessageDelta(
			let threadID,
			let turnID,
			_,
			_
		), .fileChangeUpdated(
			let threadID,
			let turnID,
			_,
			_
		), .diffUpdated(
			let threadID,
			let turnID,
			_
		):
			guard acceptsContent(
				threadID: threadID,
				turnID: turnID,
				model: model
			)
			else
			{
				return
			}
		case .planUpdated(let plan):
			guard plan.threadId == model.execution.activeThreadID,
					plan.turnId == model.execution.activeTurnID
			else
			{
				return
			}
			model.execution.activePlan = plan
		case .toolProgress(
			let threadID,
			let turnID,
			_,
			let message
		):
			guard threadID == model.execution.activeThreadID,
					turnID == model.execution.activeTurnID
			else
			{
				return
			}
			model.execution.activeActivity = message
		case .interaction(let interaction):
			guard model.connection.isConnected,
					interaction.threadId == model.execution.activeThreadID,
					interaction.turnId == model.execution.activeTurnID
			else
			{
				return
			}
			model.execution.pendingInteractions.removeAll
			{
				$0.id == interaction.id
			}
			model.execution.pendingInteractions.append(interaction)
			updateAwaitingState(&model.execution)
		case .interactionResolved(
			let threadID,
			let requestID
		):
			guard model.execution.pendingInteractions.contains(where:
				{
					$0.id == requestID && $0.threadId == threadID
				})
			else
			{
				return
			}
			model.execution.pendingInteractions.removeAll
			{
				$0.id == requestID && $0.threadId == threadID
			}
			if model.execution.pendingResponses[requestID]?.context.threadID == threadID
			{
				model.execution.pendingResponses.removeValue(forKey: requestID)
				let shouldClearResponseStatus = model.execution.pendingResponses.isEmpty
					&& !model.execution.needsReconciliation
					&& !model.execution.hasUncertainRequest
					&& model.execution.state != .stopping
					&& model.execution.statusMessage?.hasPrefix(
						uncertainResponseWarningPrefix
					) == true
				if shouldClearResponseStatus
				{
					model.execution.statusMessage = nil
				}
			}
			updateAwaitingState(&model.execution)
		case .error(
			let threadID,
			let turnID,
			let message,
			let willRetry
		):
			guard threadID == model.execution.activeThreadID,
					!threadID.isEmpty,
					turnID == model.execution.activeTurnID
			else
			{
				return
			}
			model.execution.statusMessage = message
			let endsActiveTurn = !willRetry
				&& threadID == model.execution.activeThreadID
				&& turnID == model.execution.activeTurnID
			if endsActiveTurn
			{
				model.execution.state = .failed
				model.execution.activeTurnID = nil
				model.execution.pendingInteractions.removeAll()
				model.execution.pendingResponses.removeAll()
				if model.execution.commandLifetime.hasPendingCommands
				{
					model.execution.deferredTurnOutcome = .failed
					model.execution.deferredTurnMessage = message
					model.execution.reconcilingCommandOutcome = true
					model.execution.needsReconciliation = true
					model.execution.statusMessage =
						"\(message) A command has no confirmed exit; refresh this task "
							+ "before removing its checkout."
				}
				else
				{
					result.presentationCommands.append(.taskFinished)
				}
			}
		default: break
		}
		// Accepted content updates are composed before the shared publication.
		result.domainEvents.insert(
			.backendObserved(
				event,
				observedAt: observedAt
			),
			at: 0
		)
	}

	private static func recordCompletedAgentTurn(
		_ turn: CodexTurn,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		model.execution.activeThreadID = threadID
		model.execution.activeTurnID = nil
		let lifecycle = ConversationTurnStatus.lifecycle(turn.status)
		switch lifecycle
		{
		case .interrupted:
			model.execution.agentOutcome = .stopped
		case .failed:
			model.execution.agentOutcome = .failed(turn.error ?? "Codex reported a failed task.")
		default:
			model.execution.agentOutcome = .completed
		}
		model.execution.pendingInteractions.removeAll()
		model.execution.pendingResponses.removeAll()
		model.execution.pendingSteering = nil
		if model.execution.needsReconciliation
		{
			model.execution.state = .failed
			model.execution.statusMessage =
				"Codex reported a task outcome after the request timed out. "
					+ "Refresh this conversation before sending again."
		}
		else if lifecycle == .failed
		{
			model.execution.state = .failed
			model.execution.statusMessage = turn
				.error ?? "Codex reported a failed task."
		}
		else if lifecycle == .interrupted
		{
			model.execution.state = .stopped
			model.execution
				.statusMessage = "Agent interrupted."
		}
		else
		{
			model.execution.state = .completed
			model.execution.statusMessage = model.execution.stopRequested
				? "Task completed before Stop took effect."
				: "Task completed."
		}
		model.execution.outcomeMessage = model.execution.statusMessage
	}

	private static func deferCompletionForPendingCommands(_ model: inout WorkspaceModel)
	{
		if model.execution.commandLifetime.hasPendingCommands
		{
			model.execution.deferredTurnOutcome = model.execution.state
			model.execution.deferredTurnMessage = model.execution.statusMessage
			model.execution.reconcilingCommandOutcome = !model.execution.hasUncertainRequest
			model.execution.needsReconciliation = true
			model.execution.state = .stopping
			model.execution.statusMessage =
				"The agent finished this turn. An approved command is still "
					+ "awaiting its exit; Stop does not confirm command cancellation."
			model.execution.outcomeMessage = model.execution.statusMessage
		}
	}

	private static func requestCompletedTurnHistory(
		_ turn: CodexTurn,
		threadID: String,
		context: OperationContext,
		model: WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		var readContext = context
		readContext.threadID = threadID
		readContext.turnID = turn.id
		result.domainEvents.append(.completedHistoryReadRequested(ConversationReadOperation(
			context: readContext,
			commandRevision: model.execution.commandEventRevisions[threadID, default: 0],
			purpose: .completion
		)))
	}

}
