import Foundation

extension WorkspaceStoreInputs
{
	func prepareComposerCommandInput(
		_ text: String,
		steering: Bool
	) -> ComposerCommandInput
	{
		switch SlashCommandParser.parse(text)
		{
		case .error(let error):
			store.dispatch(.composerCommand(.rejected(
				store.operationContext(),
				error.message
			)))
			return .handled(nil)
		case .command(let invocation):
			if invocation.id == .plan && !invocation.trimmedArguments.isEmpty
			{
				guard !steering, WorkspaceEligibility(model: store.model).canSend
				else
				{
					store.dispatch(.composerCommand(.rejected(
						store.operationContext(),
						"Finish the active turn before sending an inline plan prompt."
					)))
					return .handled(nil)
				}
				guard let mode = capturedCollaborationMode(kind: .plan)
				else
				{
					return .handled(nil)
				}
				return .message(
					invocation.arguments,
					mode
				)
			}
			return .handled(performSlashCommand(invocation))
		case .text(let message):
			let kind = store.model.composerCommands.planModes[
				store.model.conversations.selectedConversation
			]
			if let kind
			{
				guard let mode = capturedCollaborationMode(kind: kind)
				else
				{
					return .handled(nil)
				}
				return .message(
					message,
					mode
				)
			}
			return .message(
				message,
				nil
			)
		}
	}

	private func capturedCollaborationMode(kind: CollaborationModeKind) -> CollaborationMode?
	{
		guard let selected = ComposerCommandReducer.resolvedModel(store.model)
		else
		{
			store.dispatch(.composerCommand(.rejected(
				store.operationContext(),
				"Load the model catalog before submitting in plan mode."
			)))
			return nil
		}
		return CollaborationMode(
			mode: kind,
			model: selected.id,
			reasoningEffort: store.model.preferences.selectedEffort ?? selected
				.defaultReasoningEffort
		)
	}

	@discardableResult
	func performSlashCommand(_ invocation: SlashCommandInvocation) -> WorkspaceOperationHandle?
	{
		if invocation.id == .plan && !invocation.trimmedArguments.isEmpty
		{
			return send()
		}
		let conversation = store.model.conversations.selectedConversation
		let request = SlashCommandPresentationRequest(
			context: store.operationContext(threadID: conversation.threadID),
			invocation: invocation,
			conversation: conversation,
			draft: store.model.composer.drafts[conversation] ?? ComposerDraft()
		)
		store.dispatch(.composerCommand(.requested(request)))
		return store.operation(for: request.context)
	}

	func recoverFork(
		_ request: SlashCommandPresentationRequest,
		choice: ForkRecoveryChoice
	)
	{
		store.dispatch(.composerCommand(.forkRecoveryRequested(
			request,
			choice
		)))
	}

	func acknowledgeSlashCommand(_ request: SlashCommandPresentationRequest)
	{
		store.dispatch(.composerCommand(.acknowledged(request)))
	}

	@discardableResult
	func retryPlanSettings(
		_ request: SlashCommandPresentationRequest,
		mode: CollaborationModeKind
	) -> WorkspaceOperationHandle?
	{
		guard ComposerCommandReducer.isCurrent(
			request,
			model: store.model
		),
			let captured = capturedCollaborationMode(kind: mode)
		else
		{
			return nil
		}
		let retry = SlashCommandPresentationRequest(
			context: store.operationContext(threadID: request.context.threadID),
			invocation: request.invocation,
			conversation: request.conversation,
			draft: request.draft
		)
		store.dispatch(.composerCommand(.settingsRetryRequested(
			ComposerCommandSettingsOperation(
				request: retry,
				mode: captured
			)
		)))
		return store.operation(for: retry.context)
	}

	@discardableResult
	func completeSlashCommand(
		_ request: SlashCommandPresentationRequest,
		invocation: SlashCommandInvocation
	) -> WorkspaceOperationHandle?
	{
		guard ComposerCommandReducer.isCurrent(
			request,
			model: store.model
		),
			invocation.id == request.invocation.id
		else
		{
			return nil
		}
		let selected = SlashCommandPresentationRequest(
			context: request.context,
			invocation: invocation,
			conversation: request.conversation,
			draft: request.draft
		)
		store.dispatch(.composerCommand(.requested(selected)))
		return store.operation(for: selected.context)
	}
}
