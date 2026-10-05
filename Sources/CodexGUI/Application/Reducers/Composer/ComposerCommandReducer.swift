import Foundation

/// Commands propose typed transitions and retain their workspace and draft identity.
@MainActor
enum ComposerCommandReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		guard case .composerCommand(let command) = action
		else
		{
			if case .composer(.draftEdited) = action
			{
				model.composerCommands.error = nil
			}
			if case .execution(.submissionRequested(let submission)) = action,
				model.execution.owner?.submission.isSameRequest(as: submission.context) == true,
				let mode = submission.collaborationMode
			{
				model.composerCommands.planModes[submission.conversation] = mode.mode
			}
			if case .connection(.projectOpened(
				let identity,
				_
			)) = action,
				identity == model.identity, !model.composerCommands.blocksNewWork
			{
				model.composerCommands = ComposerCommandModel()
			}
			return result
		}
		switch command
		{
		case .requested(let request):
			guard isCurrent(
				request,
				model: model
			)
			else
			{
				return result
			}
			model.composerCommands.error = nil
			if let reason = unavailableReason(
				request.invocation.id,
				model: model
			)
			{
				model.composerCommands.error = reason
				return result
			}
			result = perform(
				request,
				model: &model
			)
		case .acknowledged(let request):
			guard isCurrent(
				request,
				model: model
			),
				model.lifecycle.cleanupReservation == nil, model.lifecycle.quitReservation == nil
			else
			{
				return result
			}
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .rejected(
			let context,
			let message
		):
			if ExecutionReducer.valid(
				context,
				model
			)
			{
				model.composerCommands.error = message
			}
		case .forkRecoveryRequested(
			let request,
			let choice
		):
			return recoverFork(
				request,
				choice: choice,
				model: &model
			)
		case .forkFinished(
			let request,
			let observation
		):
			finishFork(
				request,
				observation: observation,
				model: &model,
				result: &result
			)
		case .compactAcknowledged(
			let operation,
			let observation
		):
			finishCompactTransport(
				operation,
				observation: observation,
				model: &model,
				result: &result
			)
		case .reviewAcknowledged(
			let operation,
			let observation
		):
			finishReviewTransport(
				operation,
				observation: observation,
				model: &model,
				result: &result
			)
		case .settingsRetryRequested(let operation):
			guard isCurrent(
				operation.request,
				model: model
			),
				model.composerCommands.pendingSettings?.outcomeUncertain == true,
				model.composerCommands.pendingSettings?.request.conversation == operation.request
				.conversation,
				model.connection.isConnected, !model.execution.isTaskActive,
				model.lifecycle.cleanupReservation == nil, model.lifecycle.quitReservation == nil
			else
			{
				return result
			}
			var retry = operation
			retry.retryingUnknownMode = true
			model.composerCommands.pendingSettings = retry
			model.composerCommands.error = nil
			result.effects = [.updateCommandSettings(retry)]
		case .settingsFinished(
			let operation,
			let observation
		):
			finishSettings(
				operation,
				observation: observation,
				model: &model,
				result: &result
			)
		case .backendObserved(
			let context,
			let event
		):
			guard ExecutionReducer.valid(
				context,
				model
			)
			else
			{
				return result
			}
			observe(
				event,
				model: &model,
				result: &result
			)
		}
		return result
	}

	static func isCurrent(
		_ request: SlashCommandPresentationRequest,
		model: WorkspaceModel
	) -> Bool
	{
		ExecutionReducer.valid(
			request.context,
			model
		)
			&& request.context.threadID == request.conversation.threadID
			&& model.conversations.selectedConversation == request.conversation
			&& (model.composer.drafts[request.conversation] ?? ComposerDraft()) == request.draft
	}

	static func unavailableReason(
		_ id: SlashCommandID,
		model: WorkspaceModel
	) -> String?
	{
		if model.lifecycle.cleanupReservation != nil || model.lifecycle.quitReservation != nil
		{
			return "Commands are unavailable while this checkout is being closed."
		}
		let eligibility = WorkspaceEligibility(model: model)
		switch id
		{
		case .status, .copy, .diff, .model, .reasoning, .fast, .permissions:
			return nil
		case .skills, .mention:
			return eligibility.ownerAvailable ? nil : "Choose an available project checkout first."
		case .new:
			if model.conversations.boundThreadID != nil
			{
				return "This task checkout belongs to one chat. "
					+ "Select the source checkout for New Chat."
			}
			return model.composerCommands.blocksNewWork ? "Wait for the current command to finish."
				: nil
		case .resume:
			return model.composerCommands.blocksNewWork ? "Wait for the current command to finish."
				: nil
		case .fork:
			if model.composerCommands.uncertainFork != nil, model.connection.isConnected,
				!model.execution.isTaskActive
			{
				return nil
			}
			if model.lifecycle.managedWorkspace != nil || model.conversations.boundThreadID != nil
			{
				return "Fork from the source checkout; this task checkout stays bound to its chat."
			}
			fallthrough
		case .rename, .archive, .delete, .compact, .review:
			guard model.conversations.selectedConversation.threadID != nil
			else
			{
				return "Select a saved chat before using this command."
			}
			guard !model.conversations.showingArchived
			else
			{
				return "Restore the archived chat before using this command."
			}
			return eligibility.canManageThreads && !model.composerCommands.blocksNewWork
				? nil : "Finish or recover the current operation before changing this chat."
		case .plan:
			return eligibility.ownerAvailable && model.connection.isConnected
				&& (model.composerCommands.pendingSettings?.outcomeUncertain == true
					|| !model.composerCommands.blocksNewWork)
				? nil : "Connect to an available checkout and finish the current command first."
		}
	}

	private static func perform(
		_ request: SlashCommandPresentationRequest,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		let argument = request.invocation.trimmedArguments
		let context = request.context
		switch request.invocation.id
		{
		case .new:
			guard ConversationReducer.acceptsNewChat(
				context,
				model: model
			)
			else
			{
				model.composerCommands.error = "Finish the pending request "
					+ "before starting a new chat."
				return result
			}
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
			result.merge(WorkspaceFeatureComposition.reduceConversation(
				&model,
				.conversations(.newChatOpened(context))
			))
		case .resume:
			if argument.isEmpty
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			if let bound = model.conversations.boundThreadID, bound != argument
			{
				model.composerCommands.error = "This task checkout can resume only its bound chat. "
					+ "Select the source checkout to choose another chat."
				return result
			}
			guard model.connection.isConnected, model.identity.canonicalCheckoutPath != nil,
					model.conversations.pendingManagement == nil,
					!(model.execution.state.isBusy && model.execution.activeThreadID == nil)
			else
			{
				model.composerCommands.error = "Connect and finish the pending "
					+ "request before resuming."
				return result
			}
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
			var selection = context
			selection.threadID = argument
			result.merge(WorkspaceFeatureComposition.reduceConversation(
				&model,
				.conversations(.selectionRequested(selection))
			))
		case .rename:
			if argument.isEmpty
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			result = ConversationReducer.reduce(
				&model,
				.conversations(.managementRequested(
					.rename(
						context: context,
						name: argument
					)
				))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .archive:
			result = ConversationReducer.reduce(
				&model,
				.conversations(.managementRequested(.archive(context)))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .fork:
			if model.composerCommands.uncertainFork != nil
			{
				model.composerCommands.forkRecoveryPresentation = request
				model.composerCommands.forkRecoveryListReady = false
				return ConversationReducer.reduce(
					&model,
					.conversations(.threadListRequested(
						ConversationListOperation(
							context: request.context,
							archived: false,
							boundThreadID: nil
						)
					))
				)
			}
			model.composerCommands.pendingFork = request
			result.effects = [.forkConversation(request)]
		case .compact:
			result = startTurnCommand(
				request,
				kind: .compact,
				model: &model
			)
		case .review:
			if argument.isEmpty
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			guard let target = reviewTarget(argument)
			else
			{
				model.composerCommands.error = "Choose an uncommitted, base, "
					+ "commit, or custom review."
				return result
			}
			result = startTurnCommand(
				request,
				kind: .review(target),
				model: &model
			)
		case .model:
			if argument.isEmpty
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			guard model.preferences.models.contains(where:
				{
					$0.id == argument
				})
			else
			{
				model.composerCommands.error = "Model \(argument) is unavailable. "
					+ "Use /model to choose."
				return result
			}
			result = PreferenceReducer.reduce(
				&model,
				.preferences(.modelSelected(
					context,
					argument
				))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .reasoning:
			if argument.isEmpty
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			guard resolvedModel(model)?.supportedReasoningEfforts.contains(argument) == true
			else
			{
				model.composerCommands.error = "Reasoning effort \(argument) is "
					+ "unavailable for this model."
				return result
			}
			result = PreferenceReducer.reduce(
				&model,
				.preferences(.effortSelected(
					context,
					argument
				))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .fast:
			let enabled = argument.isEmpty ? !model.preferences.runPreferences.fastMode
				: argument == "on"
			if enabled, let reason = FastModeAvailability.unavailableReason(in: model)
			{
				model.composerCommands.error = reason
				return result
			}
			result = PreferenceReducer.reduce(
				&model,
				.preferences(.fastModeSelected(
					context,
					enabled
				))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .permissions:
			if argument.isEmpty || argument == "full"
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			let mode: ApprovalMode = argument == "auto" ? .approveForMe : .askForApproval
			result = PreferenceReducer.reduce(
				&model,
				.preferences(.approvalModeSelected(
					context,
					mode
				))
			)
			consumeDraft(
				request,
				model: &model,
				result: &result
			)
		case .plan:
			if model.composerCommands.pendingSettings?.outcomeUncertain == true
			{
				result.presentationCommands = [.slashCommand(request)]
				return result
			}
			guard argument.isEmpty
			else
			{
				model.composerCommands.error = "Submit the inline plan prompt through Send."
				return result
			}
			guard !model.execution.isTaskActive, !model.execution.needsReconciliation
			else
			{
				model.composerCommands.error = "Finish or recover the active "
					+ "turn before changing plan mode."
				return result
			}
			guard let selectedModel = resolvedModel(model)
			else
			{
				model.composerCommands.error = "Load the model catalog before changing plan mode."
				return result
			}
			let nextMode: CollaborationModeKind =
				model.composerCommands.planModes[request.conversation] == .plan ? .default : .plan
			let reasoningEffort = model.preferences.selectedEffort
				?? selectedModel.defaultReasoningEffort
			let mode = CollaborationMode(
				mode: nextMode,
				model: selectedModel.id,
				reasoningEffort: reasoningEffort
			)
			if context.threadID == nil
			{
				model.composerCommands.planModes[request.conversation] = nextMode
				consumeDraft(
					request,
					model: &model,
					result: &result
				)
			}
			else
			{
				let operation = ComposerCommandSettingsOperation(
					request: request,
					mode: mode
				)
				model.composerCommands.pendingSettings = operation
				result.effects = [.updateCommandSettings(operation)]
			}
		case .delete, .status, .skills, .mention, .diff, .copy:
			result.presentationCommands = [.slashCommand(request)]
		}
		return result
	}

	static func resolvedModel(_ model: WorkspaceModel) -> ModelOption?
	{
		if let id = model.preferences.selectedModelID
		{
			return model.preferences.models.first(where:
				{
					$0.id == id
				})
		}
		return model.preferences.models.first(where: \.isDefault)
	}

	private static func reviewTarget(_ argument: String) -> ReviewTarget?
	{
		if argument == "uncommitted"
		{
			return .uncommittedChanges
		}
		let parts = argument.split(
			maxSplits: 1,
			whereSeparator: \.isWhitespace
		)
		guard parts.count == 2
		else
		{
			return nil
		}
		let value = String(parts[1])
		switch parts[0]
		{
		case "base": return .baseBranch(branch: value)
		case "commit": return .commit(
				sha: value,
				title: nil
			)
		case "custom": return .custom(instructions: value)
		default: return nil
		}
	}

	static func consumeDraft(
		_ request: SlashCommandPresentationRequest,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard ExecutionReducer.valid(
			request.context,
			model
		),
			(model.composer.drafts[request.conversation] ?? ComposerDraft()) == request.draft,
			case .command(let source) = SlashCommandParser.parse(request.draft.text),
			source.id == request.invocation.id
		else
		{
			return
		}
		var cleared = request.draft
		cleared.text = ""
		cleared.revision += 1
		ComposerReducer.persist(
			cleared,
			conversation: request.conversation,
			context: request.context,
			model: &model,
			result: &result
		)
	}
}
