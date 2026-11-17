import Foundation

extension ComposerCommandReducer
{
	static func canEditSentPrompts(
		threadID: String,
		model: WorkspaceModel
	) -> Bool
	{
		!model.lifecycle.isShutdown && model.composerCommands.uncertainFork == nil
			&& model.conversations.selectedConversation == .thread(threadID)
			&& unavailableReason(
				.fork,
				model: model
			) == nil
	}

	static func editablePromptEntryIDs(
		threadID: String,
		model: WorkspaceModel
	) -> Set<String>
	{
		guard canEditSentPrompts(
			threadID: threadID,
			model: model
		),
			let content = model.conversations.content[.thread(threadID)]
		else
		{
			return []
		}
		return Set(content.loadedTurns.compactMap
		{
			turn in
			editableItem(in: turn).map
			{
				"\(turn.id):\($0.id)"
			}
		})
	}

	private static func editableItem(in turn: CodexTurn) -> CodexItem?
	{
		guard ConversationTurnStatus.isTerminal(turn.status),
				let first = turn.items.first(where:
				{
					$0.type == "userMessage"
				}),
				first.isEditablePrompt
		else
		{
			return nil
		}
		return first
	}

	static func editableSentPrompt(
		threadID: String,
		entryID: String,
		model: WorkspaceModel
	) -> (text: String, attachments: [ComposerContextItem])?
	{
		let conversation = ConversationKey.thread(threadID)
		guard canEditSentPrompts(
			threadID: threadID,
			model: model
		),
			let identity = ConversationEntryIdentity(entryID),
			let turn = model.conversations.content[conversation]?.loadedTurns.first(where:
				{
					$0.id == identity.turnID
				}), let item = editableItem(in: turn),
			item.id == identity.itemID
		else
		{
			return nil
		}
		return UserMessagePresenter.editablePrompt(for: item)
	}

	static func acceptsForkBoundary(
		_ request: SlashCommandPresentationRequest,
		model: WorkspaceModel
	) -> Bool
	{
		guard let boundary = request.forkBoundary
		else
		{
			return request.sentPromptRevision == nil
		}
		guard request.invocation.id == .fork, let threadID = request.context.threadID
		else
		{
			return false
		}
		switch boundary
		{
		case .throughTurn(let turnID):
			return request.sentPromptRevision == nil
				&& canBranch(
					threadID: threadID,
					turnID: turnID,
					model: model
				)
		case .beforeTurn(let turnID):
			guard let revision = request.sentPromptRevision,
					ConversationEntryIdentity(revision.entryID)?.turnID == turnID,
					let original = editableSentPrompt(
					threadID: threadID,
					entryID: revision.entryID,
					model: model
					)
			else
			{
				return false
			}
			return original.text != revision.text
				&& original.attachments == revision.attachments
				&& (!revision.attachments.isEmpty
					|| !revision.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
		}
	}

	static func prepareRevision(
		_ request: SlashCommandPresentationRequest,
		threadID: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	) -> PendingSentPromptSubmission?
	{
		let conversation = ConversationKey.thread(threadID)
		guard let revision = request.sentPromptRevision, model.composer.drafts[conversation] == nil
		else
		{
			return nil
		}
		var context = request.context
		context.threadID = threadID
		ComposerReducer.persist(
			ComposerDraft(
				text: revision.text,
				context: revision.attachments,
				revision: 1
			),
			conversation: conversation,
			context: context,
			model: &model,
			result: &result
		)
		guard let draft = model.composer.drafts[conversation]
		else
		{
			return nil
		}
		return PendingSentPromptSubmission(
			context: context,
			conversation: conversation,
			draft: draft
		)
	}

	static func submitRevisionAfterSelection(
		_ operation: ConversationReadOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard operation.purpose == .selection,
				let revision = model.composerCommands.pendingRevision,
				revision.context == operation.context
		else
		{
			return
		}
		model.composerCommands.pendingRevision = nil
		guard validRevisionOwner(
			revision,
			model: model
		)
		else
		{
			return
		}
		let project = model.contextNavigation
		let skills = ProjectProductivity.resolvedSkill(
			context: project.projectContext,
			in: project.skillCatalog
		)
		let submission = ComposerSubmission(
			context: revision.context,
			conversation: revision.conversation,
			draft: revision.draft,
			inputs: [.text(ProjectProductivity.requestText(
				context: project.projectContext,
				draft: revision.draft.text
			))],
			skills: skills.map
			{
				[$0]
			} ?? [],
			modelID: model.composerSelection.modelID,
			effort: model.composerSelection.effort,
			preferences: model.runPreferencesForSubmission,
			retainedContextRequestID: UUID(),
			projectContextRevision: project.contextRevision,
			serviceTier: model.serviceTierForSubmission,
			sendsDraftTextLiterally: true
		)
		result.merge(WorkspaceLifecycleReducer.reduceInputPreparation(
			&model,
			.inputPreparationRequested(.submission(submission))
		))
	}

	static func discardStaleRevision(
		_ action: WorkspaceAction,
		model: inout WorkspaceModel
	)
	{
		guard let revision = model.composerCommands.pendingRevision
		else
		{
			return
		}
		if !validRevisionOwner(
			revision,
			model: model
		)
		{
			model.composerCommands.pendingRevision = nil
		}
		else if case .conversations(.historyReceived(
			let operation,
			_
		)) = action,
			operation.purpose == .selection, operation.context == revision.context
		{
			// Accepted history starts the revision before this reducer runs.
			model.composerCommands.pendingRevision = nil
		}
	}

	private static func validRevisionOwner(
		_ revision: PendingSentPromptSubmission,
		model: WorkspaceModel
	) -> Bool
	{
		revision.context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
			&& model.conversations.selectedConversation == revision.conversation
			&& model.composer.drafts[revision.conversation] == revision.draft
	}
}
