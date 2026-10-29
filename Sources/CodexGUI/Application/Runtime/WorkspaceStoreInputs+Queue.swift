import Foundation

extension WorkspaceStoreInputs
{
	func removeQueuedMessage(
		_ id: UUID,
		editing: Bool
	)
	{
		if !editing,
			store.model.composer.serverQueues[store.model.conversations.selectedConversation]?
			.authority == .server,
			store.model.composer.drafts[store.model.conversations.selectedConversation]?
			.queuedMessages.first(where:
			{
				$0.id == id
			})?.serverID != nil
		{
			_ = requestServerQueue(.delete(id))
			return
		}
		let context = store
			.operationContext(threadID: store.model.conversations.selectedConversation.threadID)
		store.dispatch(.composer(.queuedMessageRemoved(
			context,
			id,
			edit: editing
		)))
	}

	@discardableResult
	private func startQueuedMessage(
		conversation: ConversationKey,
		resuming: Bool = false,
		messageID: UUID? = nil
	) -> WorkspaceOperationHandle?
	{
		var scoped = store.model
		scoped.conversations.selectedConversation = conversation
		guard resuming ? WorkspaceEligibility(model: scoped).canResumeQueue :
			WorkspaceEligibility(model: scoped).canAutomaticallyStartQueue(in: conversation),
			let messages = store.model.composer.drafts[conversation]?.queuedMessages,
			let message = messageID.flatMap(
				{
					id in messages.first
					{
						$0.id == id
					}
				}
			) ?? messages
			.first,
			!ComposerReducer.queueMessageIsReserved(
				message.id,
				model: store.model
			)
		else
		{
			return nil
		}
		guard let submission = queuedSubmission(
			message,
			conversation: conversation,
			steering: false
		)
		else
		{
			return nil
		}

		guard WorkspaceEligibility(model: scoped).acceptsPreparation(.submission(submission))
		else
		{
			return nil
		}
		store
			.dispatch(.composer(resuming ? .queuedMessageResumeRequested(submission) :
					.queuedMessageStartRequested(submission)))
		return store.operation(for: submission.context)
	}

	@discardableResult
	func resumeMessageQueue() -> WorkspaceOperationHandle?
	{
		if store.model.composer.serverQueues[store.model.conversations.selectedConversation]?
			.authority == .server
		{
			return requestServerQueue(.resume(nil))
		}
		return startQueuedMessage(
			conversation: store.model.conversations.selectedConversation,
			resuming: true
		)
	}

	func reorderQueuedMessages(_ ids: [UUID])
	{
		if store.model.composer.serverQueues[store.model.conversations.selectedConversation]?
			.authority == .server
		{
			_ = requestServerQueue(.reorder(ids))
			return
		}
		store.dispatch(.composer(.queuedMessagesReordered(
			queueContext(),
			ids
		)))
	}

	func beginEditingQueuedMessage(_ message: QueuedComposerMessage)
	{
		store.dispatch(.composer(.queuedMessageEditBegan(
			queueContext(),
			message
		)))
	}

	func cancelQueuedMessageEdit()
	{
		store.dispatch(.composer(.queuedMessageEditCancelled(queueContext())))
	}

	func setQueueingEnabled(_ enabled: Bool)
	{
		store.dispatch(.composer(.queueingEnabledChanged(
			queueContext(),
			enabled
		)))
	}

	@discardableResult
	func steerQueuedMessage(_ id: UUID) -> WorkspaceOperationHandle?
	{
		let conversation = store.model.conversations.selectedConversation
		if store.model.composer.serverQueues[conversation]?.authority == .server
		{
			if WorkspaceEligibility(model: store.model).canResumeQueue
			{
				return requestServerQueue(.resume(id))
			}
			return nil
		}
		if WorkspaceEligibility(model: store.model).canResumeQueue
		{
			return startQueuedMessage(
				conversation: conversation,
				resuming: true,
				messageID: id
			)
		}
		guard WorkspaceEligibility(model: store.model).canSteer,
				let message = store.model.composer.drafts[conversation]?.queuedMessages
				.first(where:
				{
					$0.id == id
				}),
				!ComposerReducer.queueMessageIsReserved(
				id,
				model: store.model
				),
				let submission = queuedSubmission(
				message,
				conversation: conversation,
				steering: true
				)
		else
		{
			return nil
		}
		store.dispatch(.workspaceLifecycle(.inputPreparationRequested(.steering(SteeringOperation(
			context: submission.context,
			submission: submission
		)))))
		return store.operation(for: submission.context)
	}

	private func queueContext() -> OperationContext
	{
		store.operationContext(threadID: store.model.conversations.selectedConversation.threadID)
	}

	private func queuedSubmission(
		_ message: QueuedComposerMessage,
		conversation: ConversationKey,
		steering: Bool
	) -> ComposerSubmission?
	{
		var context = store.operationContext(threadID: conversation.threadID)
		if steering
		{
			context.turnID = store.model.execution.activeTurnID
		}

		let draft = ComposerDraft(
			text: message.text,
			context: message.context
		)
		guard let text = ComposerPromptText.submittedText(
			message.text,
			collaborationMode: message.collaborationMode
		)
		else
		{
			return nil
		}
		return ComposerSubmission(
			context: context,
			conversation: conversation,
			draft: draft,
			inputs: [.text(ProjectProductivity.requestText(
				context: store.model.contextNavigation.projectContext,
				draft: text
			))],
			skills: message.skills,
			modelID: message.modelID,
			effort: message.effort,
			preferences: message.preferences,
			retainedContextRequestID: UUID(),
			projectContextRevision: store.model.contextNavigation.contextRevision,
			collaborationMode: message.collaborationMode,
			serviceTier: message.serviceTier,
			queuedMessageID: message.id,
			serverQueueEntry: steering ? store.model.composer.serverQueues[conversation]?.entries
				.first
				{
					$0.localID == message.id && $0.id == message.serverID
				} : nil,
			queueSteeringTransfer: steering && message.steeringPhase != nil,
			queuedSteeringInput: message.steeringInputJSON
		)
	}

	func continueMessageQueues()
	{
		_ = synchronizeServerQueues()
		for conversation in store.model.composer.drafts.keys
		{
			if ComposerReducer.queueNeedsSettlement(
				conversation,
				model: store.model
			)
			{
				store.dispatch(.composer(.queueLifecycleSettled(
					store.operationContext(threadID: conversation.threadID),
					conversation
				)))
			}
		}
		for conversation in store.model.composer.automaticQueueConversations
		{
			guard !store.factoryDependencies.service.canProbeThreadQueue || store.model.composer
				.serverQueues[conversation]?.authority == .local,
				store.model.execution(for: conversation).agentOutcome == .completed
			else
			{
				continue
			}
			if startQueuedMessage(conversation: conversation) != nil
			{
				return
			}
		}
	}
}
