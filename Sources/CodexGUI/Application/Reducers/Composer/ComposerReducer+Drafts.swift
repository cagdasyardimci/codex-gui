import Foundation

/// Composer editable draft hydration, revisions, context, and ordered persistence.
extension ComposerReducer
{
	static func reduceComposer(
		_ action: ComposerAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .queuedSteeringDetached, .serverQueueRequested, .serverQueueEnqueueBegan,
				.serverQueueMutationAccepted,
				.serverQueueFinished:
			reduceServerQueue(
				action,
				model: &model,
				result: &result
			)
		case .messageQueued, .queuedMessageRemoved, .queuedMessageStartRequested,
				.queuedMessageResumeRequested,
				.queuedMessagesReordered, .queuedMessageEditBegan, .queuedMessageResubmitted,
				.queuedMessageEditCancelled, .queueingEnabledChanged, .queueLifecycleSettled:
			reduceQueue(
				action,
				model: &model,
				result: &result
			)
		case .conversationRestored(
			let context,
			let conversation,
			let draft,
			let references
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			model.composer.workspace = context.workspace

			if model.composer.drafts[conversation] == nil
			{
				let restored = hydratedDraft(
					draft,
					conversation: conversation,
					model: &model
				)
				restorePausedQueue(
					restored,
					conversation: conversation,
					context: context,
					model: &model,
					result: &result
				)
			}
			mergeReferences(
				references,
				conversation: conversation,
				model: &model
			)
		case .draftRestored(
			let context,
			let conversation,
			let draft
		):
			guard valid(
				context,
				model
			), model.composer.drafts[conversation] == nil
			else
			{
				return
			}
			let restored = hydratedDraft(
				draft,
				conversation: conversation,
				model: &model
			)
			restorePausedQueue(
				restored,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .referencesLoaded(
			let context,
			let conversation,
			let references
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			mergeReferences(
				references,
				conversation: conversation,
				model: &model
			)
		case .draftEdited(
			let context,
			let conversation,
			let text,
			let revision
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			guard revision > draft.revision
			else
			{
				return
			}
			draft.text = text
			draft.revision = revision
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .contextAttached(
			let context,
			let conversation,
			let item,
			let revision
		), .referenceReused(
			let context,
			let conversation,
			let item,
			let revision
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			guard revision > draft.revision
			else
			{
				return
			}
			draft.context.append(item)
			draft.revision = revision
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .contextRemoved(
			let context,
			let conversation,
			let itemID,
			let revision
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			var draft = model.composer.drafts[conversation] ?? ComposerDraft()
			guard revision > draft.revision
			else
			{
				return
			}
			draft.context.removeAll
			{
				$0.id == itemID
			}
			draft.revision = revision
			persist(
				draft,
				conversation: conversation,
				context: context,
				model: &model,
				result: &result
			)
		case .submissionReleaseFinished:
			reduceSubmissionRelease(
				action,
				model: &model,
				result: &result
			)
		case .draftPersistenceFinished(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			),
				let conversation = model.composer.pendingDraftWrites.first(where:
					{
						$0.value == context.requestID
					})?.key
			else
			{
				return
			}
			model.composer.pendingDraftWrites.removeValue(forKey: conversation)
			switch observation
			{
			case .failed(let failure):
				model.composer.persistenceFailure = ComposerPersistenceFailure(
					context: context,
					key: .draft(conversation),
					message: failure.message
				)
			case .succeeded:
				clearPersistenceFailure(
					.draft(conversation),
					workspace: context.workspace,
					model: &model
				)
			}
		}
	}

	private static func restorePausedQueue(
		_ restored: ComposerDraft,
		conversation: ConversationKey,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		var draft = restored
		guard !draft.queuedMessages.isEmpty || draft.queuedMessageEdit != nil
		else
		{
			model.composer.drafts[conversation] = draft
			return
		}
		draft.queuePaused = !draft.queuedMessages.isEmpty
		draft.queuedMessageEdit = nil
		draft.revision += 1
		persist(
			draft,
			conversation: conversation,
			context: context,
			model: &model,
			result: &result
		)
	}

	static func persist(
		_ draft: ComposerDraft,
		conversation: ConversationKey,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		var draft = hydratedDraft(
			draft,
			conversation: conversation,
			model: &model
		)
		if draft.queuedMessages.isEmpty && draft
			.queuedMessageEdit == nil
		{
			draft.queuePaused = false
		}
		model.composer.drafts[conversation] = draft
		if model.identity.canonicalCheckoutPath != nil
		{
			model.composer.pendingDraftWrites[conversation] = context.requestID
			result.effects.append(.persistDraft(WorkspaceDraftWrite(
				context: context,
				conversation: conversation,
				draft: draft
			)))
		}
	}
	private static func hydratedDraft(
		_ value: ComposerDraft,
		conversation: ConversationKey,
		model: inout WorkspaceModel
	) -> ComposerDraft
	{
		var draft = value
		if conversation == .newChat, let lifetime = model.composer.pendingNewChatLifetime
		{
			draft.lifetime = max(
				draft.lifetime,
				lifetime
			)
			model.composer.pendingNewChatLifetime = nil
		}
		return draft
	}

}
