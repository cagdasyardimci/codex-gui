import Foundation

extension ComposerReducer
{
	static func reduceQueue(
		_ action: ComposerAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .queueLifecycleSettled(
			let context,
			let conversation
		):
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			var draft = model.composer.drafts[conversation],
			queueNeedsSettlement(
				conversation,
				model: model
			)
			else
			{
				return
			}
			if shouldPauseQueue(
				conversation,
				model: model
			)
			{
				draft.queuePaused = !draft.queuedMessages.isEmpty
				model.composer.automaticQueueConversations.remove(conversation)
			}
			draft.queuedMessageEdit = nil
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .messageQueued(
			let context,
			let message
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			WorkspaceEligibility(model: model).canQueue,
			var draft = model.composer.drafts[conversation],
			draft.text == message.text, draft.context == message.context,
			!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft
			.context.isEmpty
			else
			{
				return
			}
			draft.queuedMessages.append(message)
			draft.text = ""
			draft.context = []
			draft.revision += 1
			if !draft
				.queuePaused
			{
				model.composer.automaticQueueConversations.insert(conversation)
			}
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .queuedMessageRemoved(
			let context,
			let id,
			let editing
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			var draft = model.composer.drafts[conversation],
			let message = draft.queuedMessages.first(where:
				{
					$0.id == id
				}),
			!queueMessageIsReserved(
				id,
				model: model
			),
			!editing || (draft.text.isEmpty && draft.context.isEmpty)
			else
			{
				return
			}

			if editing
			{
				reduceQueue(
					.queuedMessageEditBegan(
						context,
						message
					),
					model: &model,
					result: &result
				)
				return
			}
			draft.queuedMessages.removeAll
			{
				$0.id == id
			}
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .queuedMessagesReordered(
			let context,
			let ids
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			var draft = model.composer.drafts[conversation],
			ComposerQueueOrdering.isPermutation(
				ids,
				of: draft.queuedMessages
			),
			!draft.queuedMessages
			.contains(where:
				{
					queueMessageIsReserved(
						$0.id,
						model: model
					)
				})
			else
			{
				return
			}
			draft.queuedMessages = ComposerQueueOrdering.reordered(
				draft.queuedMessages,
				by: ids
			)
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .queuedMessageEditBegan(
			let context,
			let original
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			var draft = model.composer.drafts[conversation], draft.queuedMessageEdit == nil,
			draft.text.isEmpty, draft.context.isEmpty,
			let index = draft.queuedMessages.firstIndex(of: original),
			!queueMessageIsReserved(
				original.id,
				model: model
			)
			else
			{
				return
			}
			draft.queuedMessages.remove(at: index)
			draft.queuedMessageEdit = QueuedComposerEdit(
				message: original,
				position: index
			)
			draft.text = original.text
			draft.context = original.context
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .queuedMessageResubmitted(
			let context,
			let captured
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			WorkspaceEligibility(model: model).canResubmitQueuedMessage,
			var draft = model.composer.drafts[conversation], draft == captured,
			let edit = draft.queuedMessageEdit,
			!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft
			.context.isEmpty
			else
			{
				return
			}
			let message = edit.message.editing(
				text: draft.text,
				context: draft.context
			)
			draft.queuedMessages.insert(
				message,
				at: min(
					max(
						0,
						edit.position
					),
					draft.queuedMessages.count
				)
			)
			draft.queuedMessageEdit = nil
			draft.text = ""
			draft.context = []
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .queuedMessageEditCancelled(let context):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID,
			var draft = model.composer.drafts[conversation],
			let edit = draft.queuedMessageEdit
			else
			{
				return
			}
			draft.queuedMessages.insert(
				edit.message,
				at: min(
					max(
						0,
						edit.position
					),
					draft.queuedMessages.count
				)
			)
			draft.queuedMessageEdit = nil
			draft.text = ""
			draft.context = []
			draft.revision += 1
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)

		case .queueingEnabledChanged(
			let context,
			let enabled
		):
			let conversation = model.conversations.selectedConversation
			guard valid(
				context,
				model
			), context.threadID == conversation.threadID
			else
			{
				return
			}
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			draft.queueingEnabled = enabled
			draft.revision += 1
			if !enabled
			{
				draft.queuedMessageEdit = nil
			}
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)

		case .queuedMessageStartRequested(let submission),
				.queuedMessageResumeRequested(let submission):
			let resuming: Bool
			if case .queuedMessageResumeRequested = action
			{
				resuming = true
			}
			else
			{
				resuming = false
			}
			let operation = ComposerInputPreparationOperation.submission(submission)
			guard submission.queuedMessageID != nil,
					(resuming ? WorkspaceEligibility(model: model).canResumeQueue :
					WorkspaceEligibility(model: model)
					.canAutomaticallyStartQueue(in: submission.conversation)),
					WorkspaceEligibility(model: model).acceptsPreparation(operation)
			else
			{
				return
			}
			if resuming, var draft = model.composer.drafts[submission.conversation]
			{
				if let id = submission.queuedMessageID,
					let index = draft.queuedMessages.firstIndex(where:
					{
						$0.id == id
					}), index != 0
				{
					let selected = draft.queuedMessages.remove(at: index)
					draft.queuedMessages.insert(
						selected,
						at: 0
					)
				}
				draft.queuePaused = false
				draft.revision += 1
				persist(
					draft,
					conversation: submission.conversation,
					context: submission.context,
					model: &model,
					result: &result
				)
			}
			model.composer.automaticQueueConversations.remove(submission.conversation)
			result.merge(WorkspaceLifecycleReducer.reduce(
				&model,
				.workspaceLifecycle(.inputPreparationRequested(operation))
			))
		default: break
		}
	}

	static func queueNeedsSettlement(
		_ conversation: ConversationKey,
		model: WorkspaceModel
	) -> Bool
	{
		guard let draft = model.composer.drafts[conversation],
				!draft.queuedMessages.isEmpty || draft.queuedMessageEdit != nil
		else
		{
			return false
		}
		return (!draft.queuePaused && shouldPauseQueue(
			conversation,
			model: model
		))
			||
			(draft.queuedMessageEdit != nil && model.execution(for: conversation)
				.agentOutcome == .completed)
	}

	private static func shouldPauseQueue(
		_ conversation: ConversationKey,
		model: WorkspaceModel
	) -> Bool
	{
		let execution = model.execution(for: conversation)
		let preparing = model.lifecycle.pendingInputPreparation?.submission
			.conversation == conversation
			|| model.composer.pendingSubmissions.values.contains
			{
				$0.conversation == conversation
			}
		let endedWithoutCompletion: Bool
		switch execution.agentOutcome
		{
		case .stopped, .failed: endedWithoutCompletion = true
		default: endedWithoutCompletion = false
		}
		if !model.connection.isConnected || execution.stopRequested
		{
			return true
		}
		if preparing
		{
			return false
		}
		if let state = model.composer.serverQueues[conversation], state.authority != .local
		{
			return endedWithoutCompletion || execution.state == .failed || execution
				.state == .disconnected
		}
		return execution.state == .failed || execution.state == .disconnected
			|| endedWithoutCompletion
			||
			(!execution.isTaskActive && !preparing && !model.composer
				.automaticQueueConversations.contains(conversation))
	}

	static func queueMessageIsReserved(
		_ id: UUID,
		model: WorkspaceModel
	) -> Bool
	{

		model.composer.serverQueues.contains
		{
			conversation, state in
			let draft = model.composer.drafts[conversation]
			return (state
				.pending != nil &&
				(draft?.queuedMessages.contains(where:
					{
						$0.id == id
					}) ?? false))
				|| draft?.queuedMessages.first(where:
					{
						$0.id == id
					})?.enqueueUncertain == true
		}
		|| model.lifecycle.pendingInputPreparation?.submission.queuedMessageID == id
		|| model.composer.pendingSubmissions.values.contains
		{
			$0.queuedMessageID == id
		}
	}
}
