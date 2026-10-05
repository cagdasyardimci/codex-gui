import Foundation

extension ComposerCommandReducer
{
	static func startTurnCommand(
		_ request: SlashCommandPresentationRequest,
		kind: ComposerCommandTurnOperation.Kind,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		let content = model.conversations.content[request.conversation]
		let previousTurnIDs = Set(content?.loadedTurns.map(\.id) ?? [])
		let operation = ComposerCommandTurnOperation(
			request: request,
			kind: kind,
			previousTurnIDs: previousTurnIDs
		)

		model.composerCommands.pendingTurn = operation
		model.execution.owner = ExecutionOwner(submission: request.context)
		model.execution.submissionRequest = request.context
		model.execution.activeThreadID = request.context.threadID
		model.execution.activeTurnID = nil
		model.execution.agentOutcome = nil
		model.execution.state = .running
		model.execution.statusMessage = request.invocation.id == .compact
			? "Requesting context compaction…" : "Starting review…"
		model.execution.outcomeMessage = nil
		model.execution.deferredTurnOutcome = nil
		model.execution.deferredTurnMessage = nil
		model.execution.stopRequested = false
		model.execution.stopContext = nil
		model.execution.interruptRequestSent = false
		model.execution.pendingInterruption = nil
		model.execution.activePlan = nil
		model.execution.activeActivity = nil

		let effect: WorkspaceEffect
		switch kind
		{
		case .compact: effect = .compactConversation(operation)
		case .review: effect = .startConversationReview(operation)
		}
		return WorkspaceReduction(effects: [effect])
	}

	static func finishFork(
		_ request: SlashCommandPresentationRequest,
		observation: OperationResult<ThreadDetail>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard ExecutionReducer.valid(
			request.context,
			model
		),
			model.composerCommands.pendingFork?.context == request.context
		else
		{
			return
		}
		model.composerCommands.pendingFork = nil
		switch observation
		{
		case .failed(let failure):
			model.composerCommands.error = "Could not fork this chat: \(failure.message)"
			if failure.outcomeIsUncertain
			{
				model.composerCommands.uncertainFork = request.context
				model.composerCommands.error = "The fork outcome is uncertain. Reconnect and "
					+ "use /fork to inspect chats or continue the original. \(failure.message)"
			}
		case .succeeded(let detail):
			guard detail.summary.cwd == request.context.workspace.canonicalCheckoutPath,
					detail.summary.id != request.context.threadID
			else
			{
				model.composerCommands.uncertainFork = request.context
				model.composerCommands.error = "Codex returned a fork with an unexpected "
					+ "checkout or ID."
				return
			}
			model.conversations.threads.removeAll
			{
				$0.id == detail.summary.id
			}
			model.conversations.threads.insert(
				detail.summary,
				at: 0
			)
			result.domainEvents.append(.historyAccepted(
				detail,
				threadID: detail.summary.id
			))
			if isCurrent(
				request,
				model: model
			), model.conversations.boundThreadID == nil
			{
				consumeDraft(
					request,
					model: &model,
					result: &result
				)
				var selection = request.context
				selection.threadID = detail.summary.id
				result.merge(WorkspaceFeatureComposition.reduceConversation(
					&model,
					.conversations(.selectionRequested(selection))
				))
			}
		}
	}

	static func finishCompactTransport(
		_ operation: ComposerCommandTurnOperation,
		observation: OperationResult<Void>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard ownsTurnCommand(
			operation,
			model: model
		)
		else
		{
			return
		}
		switch observation
		{
		case .failed(let failure):
			failTurnCommand(
				failure,
				model: &model
			)
		case .succeeded:
			model.composerCommands.pendingTurn?.transportFinished = true
			model.execution.submissionRequest = nil
			consumeDraft(
				operation.request,
				model: &model,
				result: &result
			)
			if model.execution.agentOutcome == nil
			{
				model.execution.statusMessage = "Compaction accepted. Waiting for completion…"
			}
			settleTurnCommand(&model)
		}
	}

	static func finishReviewTransport(
		_ operation: ComposerCommandTurnOperation,
		observation: OperationResult<ReviewStartResult>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard ownsTurnCommand(
			operation,
			model: model
		)
		else
		{
			return
		}
		switch observation
		{
		case .failed(let failure):
			failTurnCommand(
				failure,
				model: &model
			)
		case .succeeded(let started):
			guard started.reviewThreadId == operation.request.context.threadID,
					model.execution.owner?.submission.turnID == nil
					|| model.execution.owner?.submission.turnID == started.turn.id
			else
			{
				failTurnCommand(
					OperationFailure(
						message: "Review acknowledgement changed its owner.",
						outcomeIsUncertain: true
					),
					model: &model
				)
				return
			}
			model.composerCommands.pendingTurn?.transportFinished = true
			model.execution.submissionRequest = nil
			consumeDraft(
				operation.request,
				model: &model,
				result: &result
			)
			if model.execution.agentOutcome == nil
			{
				result.merge(ExecutionReducer.reduce(
					&model,
					.execution(.backendObserved(
						operation.request.context,
						.turnStarted(
							threadId: started.reviewThreadId,
							turn: started.turn
						)
					))
				))
				if !ConversationTurnStatus.isRunning(started.turn.status)
				{
					result.merge(ExecutionReducer.reduce(
						&model,
						.execution(.backendObserved(
							operation.request.context,
							.turnCompleted(
								threadId: started.reviewThreadId,
								turn: started.turn
							)
						))
					))
					model.composerCommands.pendingTurn?.terminalObserved = true
				}
			}
			settleTurnCommand(&model)
		}
	}

	static func finishSettings(
		_ operation: ComposerCommandSettingsOperation,
		observation: OperationResult<Void>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard ExecutionReducer.valid(
			operation.request.context,
			model
		),
			model.composerCommands.pendingSettings?.request.context == operation.request.context
		else
		{
			return
		}
		model.composerCommands.pendingSettings?.transportFinished = true
		switch observation
		{
		case .succeeded:
			settleSettings(
				operation,
				model: &model,
				result: &result
			)
		case .failed(let failure):
			if model.composerCommands.pendingSettings?.observedSettings == true
			{
				settleSettings(
					operation,
					model: &model,
					result: &result
				)
				return
			}
			let remainsUnknown = failure.outcomeIsUncertain
				|| model.composerCommands.pendingSettings?.retryingUnknownMode == true
			if !remainsUnknown
			{
				model.composerCommands.pendingSettings = nil
			}
			model.composerCommands.conversationErrors[operation.request.conversation] =
				"Could not change plan mode: \(failure.message)"
			if remainsUnknown
			{
				if !model.execution.needsReconciliation
				{
					model.composerCommands.settingsIntroducedReconciliation = true
				}
				model.execution.needsReconciliation = true
				model.composerCommands.pendingSettings?.outcomeUncertain = true
				model.composerCommands.conversationErrors[operation.request.conversation] =
					"Plan mode outcome is uncertain. Reconnect and use "
						+ "/plan to explicitly reapply Plan or reset Default. \(failure.message)"
			}
		}
	}

	static func settleSettings(
		_ operation: ComposerCommandSettingsOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		model.composerCommands.pendingSettings = nil
		model.composerCommands.planModes[operation.request.conversation] = operation.mode.mode
		if model.composerCommands.settingsIntroducedReconciliation
		{
			if !model.execution.hasUncertainRequest,
				model.composerCommands.pendingTurn == nil,
				model.composerCommands.uncertainFork == nil
			{
				model.execution.needsReconciliation = false
			}
			model.composerCommands.settingsIntroducedReconciliation = false
		}
		model.composerCommands.conversationErrors[operation.request.conversation] = nil
		consumeDraft(
			operation.request,
			model: &model,
			result: &result
		)
	}

	private static func ownsTurnCommand(
		_ operation: ComposerCommandTurnOperation,
		model: WorkspaceModel
	) -> Bool
	{
		ExecutionReducer.valid(
			operation.request.context,
			model
		)
			&& model.composerCommands.pendingTurn?.request.context == operation.request.context
			&& model.execution.owner?.submission
			.isSameRequest(as: operation.request.context) == true
	}

	private static func failTurnCommand(
		_ failure: OperationFailure,
		model: inout WorkspaceModel
	)
	{
		let conversation = model.composerCommands.pendingTurn?.request.conversation
		model.execution.submissionRequest = nil
		model.composerCommands.pendingTurn?.transportFinished = true
		let observedTurn = model.execution.owner?.submission.turnID != nil
		if failure.outcomeIsUncertain || observedTurn
		{
			model.execution.hasUncertainRequest = true
			model.execution.needsReconciliation = true
			model.execution.state = model.connection.isConnected ? .failed : .disconnected
			if let conversation
			{
				model.composerCommands.conversationErrors[conversation] =
					"Command outcome is uncertain. Reopen this chat to "
						+ "check its history before retrying. \(failure.message)"
			}
		}
		else
		{
			model.composerCommands.pendingTurn = nil
			model.execution.owner = nil
			model.execution.activeThreadID = nil
			model.execution.activeTurnID = nil
			model.execution.state = model.connection.isConnected ? .ready : .disconnected
			if let conversation
			{
				model.composerCommands.conversationErrors[conversation] = failure.message
			}
		}
	}

	private static func settleTurnCommand(_ model: inout WorkspaceModel)
	{
		guard let pending = model.composerCommands.pendingTurn,
				pending.transportFinished, pending.terminalObserved,
				!model.execution.hasUncertainRequest
		else
		{
			return
		}
		model.composerCommands.pendingTurn = nil
		model.composerCommands.conversationErrors[pending.request.conversation] = nil
	}

	static func observe(
		_ event: AppServerEvent,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		observeThreadState(
			event,
			model: &model,
			result: &result
		)
		guard let operation = model.composerCommands.pendingTurn
		else
		{
			return
		}
		let threadID = operation.request.context.threadID
		switch event
		{
		case .turnCompleted(
			let observedThread,
			let turn
		):
			guard observedThread == threadID, model.execution.agentOutcome != nil,
					model.execution.owner?.submission.turnID == turn.id
			else
			{
				return
			}
			model.composerCommands.pendingTurn?.terminalObserved = true
			settleTurnCommand(&model)
		case .contextCompacted(
			let observedThread,
			let turnID
		):
			guard case .compact = operation.kind, observedThread == threadID,
					!operation.previousTurnIDs.contains(turnID),
					model.execution.owner?.submission.turnID == nil
					|| model.execution.owner?.submission.turnID == turnID
			else
			{
				return
			}
			model.execution.owner?.submission.turnID = turnID
			model.execution.activeTurnID = nil
			model.execution.agentOutcome = .completed
			model.composerCommands.pendingTurn?.terminalObserved = true
			if !model.execution.hasUncertainRequest
				&& !model.execution.commandLifetime.hasPendingCommands
			{
				model.execution.state = .completed
				model.execution.statusMessage = "Context compacted."
				model.execution.outcomeMessage = model.execution.statusMessage
				model.execution.stopRequested = false
				model.execution.pendingInterruption = nil
				result.presentationCommands.append(.taskFinished)
			}
			settleTurnCommand(&model)
		default: break
		}
	}

	private static func markCommandsUncertainAfterDisconnect(_ model: inout WorkspaceModel)
	{
		if let fork = model.composerCommands.pendingFork
		{
			model.composerCommands.uncertainFork = fork.context
			model.composerCommands.pendingFork = nil
			model.composerCommands.error = "Fork may have been saved. Reconnect and use /fork "
				+ "to inspect chats or continue the original."
		}
		if let settings = model.composerCommands.pendingSettings
		{
			_ = model.reduceExecutionScope(
				model.executionIdentity(for: settings.request.conversation)
			)
			{
				model in
				if !model.execution.needsReconciliation
				{
					model.composerCommands.settingsIntroducedReconciliation = true
				}
				model.execution.needsReconciliation = true
				model.composerCommands.pendingSettings?.outcomeUncertain = true
				model.composerCommands.pendingSettings?.transportFinished = true
				return WorkspaceReduction()
			}
		}
		model.composerCommands.pendingTurn?.transportFinished = true
	}

	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch event
		{
		case .backendObserved(
			let observation,
			_
		):
			observe(
				observation,
				model: &model,
				result: &result
			)
			return result
		case .connectionDisconnected:
			markCommandsUncertainAfterDisconnect(&model)
			return result
		case .submissionAccepted(let submission):
			if let mode = submission.collaborationMode
			{
				model.composerCommands.planModes[submission.conversation] = mode.mode
			}
			return result
		case .submissionPrepared(let prepared):
			let submission = prepared.submission
			if let mode = submission.collaborationMode,
				prepared.thread.summary.cwd == submission.context.workspace.canonicalCheckoutPath
			{
				let destination = ConversationKey.thread(prepared.thread.summary.id)
				model.composerCommands.planModes[destination] = mode.mode
				let adoptedLifetime = model.composer.drafts[destination]?.lifetime
				let currentLifetime = model.composer.drafts[.newChat]?.lifetime ?? 0
				if submission.conversation == .newChat,
					model.conversations.selectedConversation == destination,
					adoptedLifetime == submission.draft.lifetime,
					currentLifetime == submission.draft.lifetime + 1
				{
					model.composerCommands.planModes.removeValue(forKey: .newChat)
				}
			}
			return result
		case .conversationListAccepted(let operation):
			if let request = model.composerCommands.forkRecoveryPresentation,
				operation.context == request.context, !operation.archived,
				isCurrent(
				request,
				model: model
				), model.composerCommands.uncertainFork != nil
			{
				model.composerCommands.forkRecoveryListReady = true
				result.presentationCommands = [.slashCommand(request)]
			}
			return result
		default: break
		}
		guard case .historyAccepted(
			let detail,
			let threadID
		) = event
		else
		{
			return WorkspaceReduction()
		}
		if let pending = model.composerCommands.pendingTurn,
			pending.request.context.threadID == threadID
		{
			let knownID = model.execution.owner?.submission.turnID
			let turn = detail.turns.first
			{
				if let knownID
				{
					return $0.id == knownID
				}
				return !pending.previousTurnIDs.contains($0.id)
					&& $0.items.contains
					{
						$0.type == "contextCompaction" || $0.type == "enteredReviewMode"
					}
			}
			if let turn, !ConversationTurnStatus.isRunning(turn.status)
			{
				model.composerCommands.pendingTurn?.terminalObserved = true
				if pending.transportFinished
				{
					model.composerCommands.pendingTurn = nil
					model.composerCommands.conversationErrors[pending.request.conversation] = nil
				}
			}
			else if model.execution.hasUncertainRequest || model.execution.agentOutcome == nil
			{
				model.execution.hasUncertainRequest = true
				model.execution.needsReconciliation = true
				model.execution.state = .failed
				model.composerCommands.conversationErrors[pending.request.conversation] =
					"This command has no confirmed terminal outcome. "
						+ "Refresh its chat again before retrying or closing the checkout."
			}
		}
		return result
	}
}
