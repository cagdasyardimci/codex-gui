import Foundation

extension ComposerCommandReducer
{
	static func recoverFork(
		_ request: SlashCommandPresentationRequest,
		choice: ForkRecoveryChoice,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		guard isCurrent(
			request,
			model: model
		), model.connection.isConnected,
		model.composerCommands.uncertainFork != nil,
		model.composerCommands.forkRecoveryPresentation?.context == request.context,
		model.composerCommands.forkRecoveryListReady,
		model.lifecycle.cleanupReservation == nil, model.lifecycle.quitReservation == nil
		else
		{
			return result
		}
		var selection = request.context
		switch choice
		{
		case .continueOriginal:
			guard let originalID = model.composerCommands.uncertainFork?.threadID,
					model.conversations.threads.contains(where:
					{
						$0.id == originalID && $0.cwd == model.identity.canonicalCheckoutPath
					})
			else
			{
				model.composerCommands.error = "Original chat is unavailable in this checkout. "
					+ "Refresh and inspect the saved chats before continuing."
				return result
			}
			selection.threadID = originalID
		case .resume(let threadID):
			guard model.conversations.threads.contains(where:
				{
					$0.id == threadID && $0.cwd == model.identity.canonicalCheckoutPath
				}), threadID != model.composerCommands.uncertainFork?.threadID,
			model.conversations.boundThreadID == nil
			else
			{
				return result
			}
			selection.threadID = threadID
		}
		model.composerCommands.uncertainFork = nil
		model.composerCommands.forkRecoveryPresentation = nil
		model.composerCommands.forkRecoveryListReady = false
		model.composerCommands.error = nil
		consumeDraft(
			request,
			model: &model,
			result: &result
		)
		if selection.threadID != request.context.threadID
		{
			result.merge(WorkspaceFeatureComposition.reduceConversation(
				&model,
				.conversations(.selectionRequested(selection))
			))
		}
		return result
	}

	static func observeThreadState(
		_ event: AppServerEvent,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		func knownThread(_ id: String) -> Bool
		{
			model.conversations.selectedConversation.threadID == id
				|| model.execution(for: .thread(id)).activeThreadID == id
				|| model.conversations.threads.contains
				{
					$0.id == id && $0.cwd == model.identity.canonicalCheckoutPath
				}
		}
		switch event
		{
		case .tokenUsageUpdated(
			let id,
			_,
			let usage
		):
			if knownThread(id)
			{
				model.composerCommands.tokenUsage[id] = usage
			}
		case .threadStatusChanged(
			let id,
			let status
		):
			if knownThread(id)
			{
				model.composerCommands.threadStatuses[id] = status
			}
		case .threadSettingsUpdated(
			let id,
			let settings
		):
			guard knownThread(id), settings.cwd == model.identity.canonicalCheckoutPath
			else
			{
				return
			}
			model.composerCommands.threadSettings[id] = settings
			if let mode = settings.collaborationMode
			{
				model.composerCommands.planModes[.thread(id)] = mode.mode
				if let operation = model.composerCommands.pendingSettings,
					operation.request.context.threadID == id, operation.mode == mode
				{
					model.composerCommands.pendingSettings?.observedSettings = true
					if operation.transportFinished
					{
						settleSettings(
							operation,
							model: &model,
							result: &result
						)
					}
				}
			}
		default: break
		}
	}

	/// A reserved command must not adopt a replayed turn from its loaded history.
	static func acceptsExecutionEvent(
		_ event: AppServerEvent,
		model: WorkspaceModel
	) -> Bool
	{
		guard let pending = model.composerCommands.pendingTurn
		else
		{
			return true
		}
		switch event
		{
		case .turnStarted(
			let id,
			let turn
		), .turnCompleted(
			let id,
			let turn
		):
			return id != pending.request.context.threadID || !pending.previousTurnIDs
				.contains(turn.id)
		case .itemStarted(
			let id,
			let turnID,
			_
		), .itemCompleted(
			let id,
			let turnID,
			_
		), .agentMessageDelta(
			let id,
			let turnID,
			_,
			_
		), .commandOutputDelta(
			let id,
			let turnID,
			_,
			_
		), .fileChangeUpdated(
			let id,
			let turnID,
			_,
			_
		), .diffUpdated(
			let id,
			let turnID,
			_
		), .toolProgress(
			let id,
			let turnID,
			_,
			_
		), .error(
			let id,
			let turnID,
			_,
			_
		):
			return id != pending.request.context.threadID || !pending.previousTurnIDs
				.contains(turnID)
		case .planUpdated(let plan):
			return plan.threadId != pending.request.context.threadID
				|| !pending.previousTurnIDs.contains(plan.turnId)
		default: return true
		}
	}
}
