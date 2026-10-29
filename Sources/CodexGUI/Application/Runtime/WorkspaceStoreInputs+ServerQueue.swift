import Foundation

extension WorkspaceStoreInputs
{
	@discardableResult
	func requestServerQueue(
		_ command: ServerQueueOperation.Command,
		conversation: ConversationKey? = nil
	) -> WorkspaceOperationHandle?
	{
		let conversation = conversation ?? store.model.conversations.selectedConversation
		let state = store.model.composer.serverQueues[conversation] ?? ServerQueueState()
		guard !hasQueuedSteering(in: conversation), state.pending == nil,
				store.model.connection.isConnected,
				conversation.threadID != nil
		else
		{
			return nil
		}
		let draft = store.model.composer.drafts[conversation] ?? ComposerDraft()
		var messages = draft.queuedMessages + (draft.queuedMessageEdit.map
		{
			[$0.message]
		} ?? [])
		switch command
		{
		case .add(let message), .update(let message):
			messages.removeAll
			{
				$0.id == message.id
			}
			messages.append(message)
		case .resume(let id):
			if let id, let index = messages.firstIndex(where:
				{
					$0.id == id
				})
			{
				messages.insert(
					messages.remove(at: index),
					at: 0
				)
			}
		default: break
		}
		let context = store.operationContext(threadID: conversation.threadID)
		let operation = ServerQueueOperation(
			context: context,
			conversation: conversation,
			revision: state.revision + 1,
			command: command,
			entries: state.entries,
			messages: messages,
			projectContext: store.model.contextNavigation.projectContext,
			draftRevision: draft.revision
		)
		store.dispatch(.composer(.serverQueueRequested(operation)))
		return store.operation(for: context)
	}

	private func hasQueuedSteering(in conversation: ConversationKey) -> Bool
	{
		let model = store.model
		if let submission = model.lifecycle.pendingInputPreparation?.submission,
			submission.conversation == conversation, submission.queuedMessageID != nil
		{
			return true
		}
		return model.composer.pendingSubmissions.values.contains
		{
			$0.conversation == conversation && $0.queuedMessageID != nil
				&& model.execution(for: conversation).pendingSteering == $0.context
		}
	}

	/// Returns true while queue ownership belongs to the server or is being probed.
	func synchronizeServerQueues() -> Bool
	{
		guard store.factoryDependencies.service.canProbeThreadQueue
		else
		{
			return false
		}
		if store.model.connection.isConnected, store.model.conversations.pendingSelection == nil,
			let threadID = store.model.conversations.selectedConversation.threadID,
			store.model.composer.drafts[.thread(threadID)] != nil,
			store.model.composer.serverQueues[.thread(threadID)] == nil
		{
			_ = requestServerQueue(
				.refresh,
				conversation: .thread(threadID)
			)
		}
		if store.model.connection.isConnected
		{
			for (conversation, draft) in store.model.composer.drafts
				where conversation.threadID != nil && !draft.queuedMessages.isEmpty && store.model
				.composer.serverQueues[conversation] == nil
			{
				_ = requestServerQueue(
					.refresh,
					conversation: conversation
				)
			}
		}
		for (conversation, state) in store.model.composer.serverQueues
		{
			if state.authority != .local, state.needsRefresh, state.pending == nil,
				store.model.connection.isConnected
			{
				_ = requestServerQueue(
					.refresh,
					conversation: conversation
				)
			}
		}
		return true
	}
}
