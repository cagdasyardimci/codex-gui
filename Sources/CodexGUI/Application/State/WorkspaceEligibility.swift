import Foundation

/// Shared canonical capability and proposal checks. Input IO stays in runtime.
struct WorkspaceEligibility
{
	let model: WorkspaceModel

	var preferenceWarning: String?
	{
		if let error = model.preferences.modelListError
		{
			return "\(error) Reconnect before sending."
		}
		let isProjectContextLoading =
			model.contextNavigation.pendingContextLoad?.revision
				== model.contextNavigation.contextRevision
		if isProjectContextLoading
		{
			return "Project context is loading."
		}
		if model.preferences.runPreferences.fastMode,
			let reason = FastModeAvailability.unavailableReason(in: model)
		{
			return "\(reason) Disable fast mode before sending."
		}
		return model.preferences.warning(skillWarning: ProjectProductivity.skillWarning(
			context: model.contextNavigation.projectContext,
			in: model.contextNavigation.skillCatalog
		))
	}

	var ownerAvailable: Bool
	{
		guard model.identity.canonicalCheckoutPath != nil,
				model.lifecycle.managedOwnershipConflict == nil,
				model.lifecycle.cleanupReservation == nil, model.lifecycle.quitReservation == nil,
				model.conversations.pendingProjectArchive == nil
		else
		{
			return false
		}
		if let owner = model.lifecycle.owner, owner.sessionID != model.identity.sessionID
		{
			return false
		}
		if let managed = model.lifecycle.managedWorkspace
		{
			guard managed.phase == .active,
					managed.checkoutPath == model.identity.canonicalCheckoutPath
			else
			{
				return false
			}
			if case .managed(
				let id,
				_
			) = model.lifecycle.owner, id != managed.id
			{
				return false
			}
		}
		if let threadID = model.conversations.boundThreadID
		{
			return model.conversations.selectedConversation == .thread(threadID)
		}
		return true
	}

	var canSend: Bool
	{
		ownerAvailable
			&& model.connection.isConnected
			&& !model.execution.isTaskActive
			&& model.execution.state != .disconnected
			&& !model.execution.needsReconciliation
			&& !model.execution.hasUncertainRequest
			&& !hasUncertainSubmission(for: model.conversations.selectedConversation)
			&& model.lifecycle.pendingInputPreparation == nil
			&& !model.conversations.showingArchived
			&& model.conversations.pendingSelection == nil
			&& model.conversations.pendingManagement == nil
			&& preferenceWarning == nil
			&& !model.composerCommands.blocksNewWork(for: model.conversations.selectedConversation)
	}

	var canSteer: Bool
	{
		ownerAvailable
			&& model.connection.isConnected
			&& model.execution.state.isBusy
			&& model.execution.state != .stopping
			&& !model.execution.stopRequested
			&& model.execution.pendingSteering == nil
			&& !model.execution.needsReconciliation
			&& !model.execution.hasUncertainRequest
			&& model.lifecycle.pendingInputPreparation == nil
			&& model.conversations.pendingManagement == nil
			&& model.conversations.pendingSelection == nil
			&& !model.composerCommands.blocksNewWork(for: model.conversations.selectedConversation)
			&& !model.conversations.showingArchived
			&& model.execution.activeTurnID != nil
			&& model.execution.activeThreadID != nil
			&& model.conversations.selectedConversation.threadID == model.execution.activeThreadID
	}

	var canManageThreads: Bool
	{
		ownerAvailable
			&& model.connection.isConnected
			&& !model.execution.isTaskActive
			&& !model.execution.needsReconciliation
			&& !model.execution.hasUncertainRequest
			&& model.composer.uncertainSubmissions.isEmpty
			&& model.lifecycle.pendingInputPreparation == nil
			&& model.conversations.pendingSelection == nil
			&& model.conversations.pendingManagement == nil
			&& !model.composerCommands.blocksNewWork
	}

	func acceptsSubmission(_ submission: ComposerSubmission) -> Bool
	{
		canSend && matches(
			submission,
			steering: false
		) && hasInput(submission)
	}

	func acceptsSteering(_ operation: SteeringOperation) -> Bool
	{
		canSteer && operation.context == operation.submission.context
			&& operation.context.threadID == model.execution.activeThreadID
			&& operation.context.turnID == model.execution.activeTurnID
			&& matches(
				operation.submission,
				steering: true
			) && hasInput(operation.submission)
	}

	func acceptsPreparation(_ operation: ComposerInputPreparationOperation) -> Bool
	{
		switch operation
		{
		case .submission(let submission):
			return canSend && matches(
				submission,
				steering: false
			)
				&& hasSourceContent(submission.draft)
		case .steering(let steering):
			return canSteer
				&& steering.context == steering.submission.context
				&& steering.context.threadID == model.execution.activeThreadID
				&& steering.context.turnID == model.execution.activeTurnID
				&& matches(
					steering.submission,
					steering: true
				)
				&& hasSourceContent(steering.submission.draft)
		}
	}

	func acceptsManagement(_ operation: ThreadManagementOperation) -> Bool
	{
		guard let threadID = operation.context.threadID, canManageThreads,
				!model.execution(for: .thread(threadID)).blocksCleanup,
				!hasUncertainSubmission(for: .thread(threadID)),
				operation.context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
				),
				threadID == model.conversations.selectedConversation.threadID
				|| model.conversations.threads.contains(where:
				{
					$0.id == threadID
				})
				|| model.preferences.pinnedTasks.contains(where:
				{
					$0.id == threadID
				})
		else
		{
			return false
		}
		switch operation
		{
		case .rename: return true
		case .delete: return true
		case .archive: return !model.conversations.showingArchived
		case .unarchive: return model.conversations.showingArchived
		}
	}

	private func hasUncertainSubmission(for conversation: ConversationKey) -> Bool
	{
		model.composer.uncertainSubmissions.contains
		{
			requestID in
			guard let submission = model.composer.pendingSubmissions[requestID]
			else
			{
				return true
			}
			let owner = model.composer.submissionConversations[requestID] ?? submission.conversation
			guard owner == conversation
			else
			{
				return false
			}
			if conversation == .newChat
			{
				return model.executionIdentity(for: conversation)
					== .newChat(lifetime: submission.draft.lifetime)
			}
			return true
		}
	}

	private func matches(
		_ submission: ComposerSubmission,
		steering: Bool
	) -> Bool
	{
		let currentDraft = model.composer.drafts[submission.conversation] ?? ComposerDraft()
		return submission.context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
			&& submission.conversation == model.conversations.selectedConversation
			&& submission.context.threadID == submission.conversation.threadID
			&& matchesCapturedDraft(
				currentDraft,
				submission: submission,
				steering: steering
			)
			&& matchesCapturedPreferences(
				submission,
				steering: steering
			)
			&& model.composer.pendingSubmissions[submission.context.requestID] == nil
	}

	private func matchesCapturedDraft(
		_ currentDraft: ComposerDraft,
		submission: ComposerSubmission,
		steering: Bool
	) -> Bool
	{
		currentDraft.revision == submission.draft.revision
			&& currentDraft.lifetime == submission.draft.lifetime
			&& currentDraft.context == submission.draft.context
			&& (steering || currentDraft.text == submission.draft.text)
	}

	private func matchesCapturedPreferences(
		_ submission: ComposerSubmission,
		steering: Bool
	) -> Bool
	{
		(submission.projectContextRevision ?? 0) == model.contextNavigation.contextRevision
			&& (steering || submission.skills == (ProjectProductivity.resolvedSkill(
				context: model.contextNavigation.projectContext,
				in: model.contextNavigation.skillCatalog
			).map
			{
				[$0]
			} ?? []))
			&& submission.modelID == model.preferences.selectedModelID
			&& submission.effort == model.preferences.selectedEffort
			&& submission.preferences == model.preferences.runPreferences
			&& (steering || !submission.preferences.fastMode
				|| submission.serviceTier == FastModeAvailability.serviceTier(in: model))
	}

	private func hasSourceContent(_ draft: ComposerDraft) -> Bool
	{
		let hasDraftText = !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		return hasDraftText || draft.context.contains
		{
			switch $0.kind
			{
			case .fileReference, .image: return $0.path?.isEmpty == false
			case .textExcerpt: return $0.path?.isEmpty == false && $0.excerpt?.isEmpty == false
			}
		}
	}

	private func hasInput(_ submission: ComposerSubmission) -> Bool
	{
		guard hasSourceContent(submission.draft),
				case .text(let text) = submission.inputs.first,
				!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			return false
		}
		guard let submittedText = ComposerPromptText.submittedText(
			submission.draft.text,
			collaborationMode: submission.collaborationMode
		)
		else
		{
			return false
		}
		let expectedRequestText = ProjectProductivity.requestText(
			context: model.contextNavigation.projectContext,
			draft: submittedText
		)
		var textParts = [expectedRequestText]
		var remainingInputs = Array(submission.inputs.dropFirst())
		guard appendValidatedContextDescriptions(
			submission.draft.context,
			remainingInputs: &remainingInputs,
			textParts: &textParts
		)
		else
		{
			return false
		}
		guard remainingInputs.isEmpty
		else
		{
			return false
		}

		let nonemptyTextParts = textParts.filter
		{
			!$0.isEmpty
		}
		let expectedSubmittedText = nonemptyTextParts.joined(separator: "\n\n")
		return text == expectedSubmittedText
	}

	private func appendValidatedContextDescriptions(
		_ items: [ComposerContextItem],
		remainingInputs: inout [TurnInput],
		textParts: inout [String]
	) -> Bool
	{
		for item in items
		{
			switch item.kind
			{
			case .fileReference:
				guard let path = item.path, let checkout = model.identity.canonicalCheckoutPath,
						case .mention(
						let name,
						let resolvedPath
						) = remainingInputs.first,
						name == URL(fileURLWithPath: path).lastPathComponent,
						resolvedPath.hasPrefix(checkout + "/")
				else
				{
					return false
				}
				textParts.append(UserMessageContextDescription.file(path: path))
				remainingInputs.removeFirst()
			case .textExcerpt:
				guard let path = item.path, let excerpt = item.excerpt
				else
				{
					continue
				}
				textParts.append(UserMessageContextDescription.excerpt(
					path: path,
					text: excerpt,
					firstLine: item.firstLine,
					lastLine: item.lastLine
				))
			case .image:
				guard let path = item.path, remainingInputs.first == .localImage(path: path)
				else
				{
					return false
				}
				textParts.append(UserMessageContextDescription.image(title: item.title))
				remainingInputs.removeFirst()
			}
		}
		return true
	}
}
