import Foundation

/// Composer captured submission preparation, acknowledgement, and uncertain release.
extension ComposerReducer
{
	static func reduceSubmissionRelease(
		_ action: ComposerAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .submissionReleaseFinished(
			let operation,
			let observation
		):
			let context = operation.context
			let submission = operation.submission
			let id = submission.context.requestID
			guard context.workspace == model.identity,
					model.composer.pendingSubmissions[id]?.context
					.isSameRequest(as: submission.context) == true,
					model.composer.resolvingSubmissions[id] == context
			else
			{
				return
			}
			if case .succeeded(let release) = observation,
				!release.submission.context.isSameRequest(as: submission.context)
			{
				return
			}
			model.composer.resolvingSubmissions.removeValue(forKey: id)
			switch observation
			{
			case .succeeded(let release):
				if let threadID = release.threadID, let references = release.references
				{
					model.composer.sentReferences[.thread(threadID)] = references
				}
				if release.released
				{
					model.composer.pendingSubmissions.removeValue(forKey: id)
					model.composer.preparedSubmissions.removeValue(forKey: id)
					model.composer.submissionConversations.removeValue(forKey: id)
					model.composer.uncertainSubmissions.remove(id)
					model.composer.acknowledgedSubmissions.remove(id)
					clearPersistenceFailure(
						.submission(id),
						workspace: context.workspace,
						model: &model
					)
				}
			case .failed(let failure):
				model.composer.uncertainSubmissions.insert(id)
				if valid(
					context,
					model
				)
				{
					model.composer.persistenceFailure = ComposerPersistenceFailure(
						context: context,
						key: .submission(id),
						message: failure.message
					)
				}
			}
		default: break
		}
	}

	static func reduceExecution(
		_ action: ExecutionAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .submissionRequested(let submission):
			guard model.execution.submissionRequest?.isSameRequest(as: submission.context) == true,
					model.execution.state == .running,
					model.composer.pendingSubmissions[submission.context.requestID] == nil
			else
			{
				return
			}
			capture(
				submission,
				model: &model
			)
		case .steeringRequested(let operation):
			guard model.execution.pendingSteering == operation.context,
					model.composer.pendingSubmissions[operation.context.requestID] == nil
			else
			{
				return
			}
			capture(
				operation.submission,
				model: &model
			)
		case .submissionPrepared(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			),
				model.execution.owner?.submission.isSameRequest(as: context) == true,
				let submission = model.composer.pendingSubmissions[context.requestID]
			else
			{
				return
			}
			switch observation
			{
			case .failed:
				model.composer.uncertainSubmissions.insert(context.requestID)
			case .succeeded(let prepared):
				adoptPreparedConversation(
					prepared,
					submission: submission,
					context: context,
					model: &model,
					result: &result
				)
			}
		case .preparedPersistenceFinished(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			),
				let submission = model.composer.pendingSubmissions[context.requestID]
			else
			{
				return
			}
			if case .failed = observation
			{
				model.composer.uncertainSubmissions.insert(context.requestID)
			}
			else if model.execution.state == .completed
			{
				finish(
					submission,
					attempt: context,
					model: &model,
					result: &result
				)
			}
		case .submissionAcknowledged(
			let context,
			let acknowledgement
		):
			guard valid(
				context,
				model
			),
				model.execution.owner?.submission.isSameRequest(as: context) == true,
				let submission = model.composer.pendingSubmissions[context.requestID]
			else
			{
				return
			}
			if model.execution.hasUncertainRequest
				|| model.composer.submissionConversations[context.requestID]
				!= .thread(acknowledgement.thread.id)
			{
				model.composer.uncertainSubmissions.insert(context.requestID)
				return
			}
			acknowledge(
				submission,
				threadID: acknowledgement.thread.id,
				model: &model,
				result: &result
			)
		case .submissionFailed(
			let context,
			_
		):
			guard valid(
				context,
				model
			), model.composer.pendingSubmissions[context.requestID] != nil
			else
			{
				return
			}
			model.composer.uncertainSubmissions.insert(context.requestID)
		case .submissionCancelledBeforeSend(let context):
			guard valid(
				context,
				model
			),
				let submission = model.composer.pendingSubmissions[context.requestID],
				model.execution.state == .completed
			else
			{
				return
			}
			finish(
				submission,
				attempt: context,
				model: &model,
				result: &result
			)
		case .submissionStartFailed(
			let context,
			let failure,
			_
		):
			guard valid(
				context,
				model
			),
				let submission = model.composer.pendingSubmissions[context.requestID]
			else
			{
				return
			}
			if failure.outcomeIsUncertain
			{
				model.composer.uncertainSubmissions.insert(context.requestID)
			}
			else
			{
				finish(
					submission,
					attempt: context,
					model: &model,
					result: &result
				)
			}
		case .steeringFinished(
			let context,
			let observation
		):
			steeringFinished(
				context,
				observation: observation,
				model: &model,
				result: &result
			)
		case .steeringTransportFinished(
			let operation,
			let observation
		):
			steeringFinished(
				operation.context,
				observation: observation,
				model: &model,
				result: &result
			)
		case .draftAcknowledgementFinished(
			let context,
			let observation
		):
			guard let submission = model.composer.pendingSubmissions[context.requestID],
					context.workspace == model.identity
			else
			{
				return
			}
			if case .succeeded(let acknowledgement) = observation
			{
				if let references = acknowledgement.references
				{
					model.composer.sentReferences[.thread(acknowledgement.threadID)] = references
				}
				finish(
					submission,
					attempt: context,
					model: &model,
					result: &result
				)
			}
			else if case .failed(let failure) = observation, valid(
				context,
				model
			)
			{
				model.composer.uncertainSubmissions.insert(context.requestID)
				model.composer.persistenceFailure = ComposerPersistenceFailure(
					context: context,
					key: .submission(context.requestID),
					message: failure.message
				)
			}
		case .reconciliationFinished(
			let context,
			let observation
		):
			guard valid(
				context,
				model
			), case .succeeded = observation,
			!model.execution.needsReconciliation,
			model.execution.lastReconciledRequestID == context.requestID
			else
			{
				return
			}
			resolveUncertain(
				threadID: context.threadID,
				attempt: context,
				model: &model,
				result: &result
			)
		case .historyObserved(
			let operation,
			let detail
		):
			guard valid(
				operation.context,
				model
			), !model.execution.needsReconciliation,
			model.execution.lastReconciledRequestID == operation.context.requestID
			else
			{
				return
			}
			resolveUncertain(
				threadID: detail.summary.id,
				attempt: operation.context,
				model: &model,
				result: &result
			)
		default: break
		}
	}

	private static func adoptPreparedConversation(
		_ prepared: PreparedSubmission,
		submission: ComposerSubmission,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		model.composer.preparedSubmissions[context.requestID] = prepared
		let destination = ConversationKey.thread(prepared.thread.summary.id)
		var transferred = submission.draft
		var clearSource = false
		var selectThread = false
		if submission.conversation == .newChat
		{
			let source = model.composer.drafts[.newChat] ?? ComposerDraft()
			if source.lifetime == submission.draft.lifetime
			{
				transferred = source
				clearSource = true
				model.composer.drafts[.newChat] = ComposerDraft(
					revision: source.revision + 1,
					lifetime: source.lifetime + 1
				)
				if model.conversations.selectedConversation == .newChat
				{
					ConversationReducer.adoptPreparedSelection(
						destination,
						model: &model
					)
					selectThread = true
				}
			}
			model.composer.drafts[destination] = transferred
		}
		model.composer.submissionConversations[context.requestID] = destination
		result.domainEvents.append(.submissionPrepared(prepared))
		result.effects.append(.persistPreparedConversation(PreparedConversationWrite(
			prepared: prepared,
			draft: transferred,
			selectThread: selectThread,
			clearSource: clearSource
		)))
	}

	private static func capture(
		_ submission: ComposerSubmission,
		model: inout WorkspaceModel
	)
	{
		model.composer.pendingSubmissions[submission.context.requestID] = submission
		model.composer.submissionConversations[submission.context.requestID] = submission
			.conversation
	}

	private static func steeringFinished(
		_ context: OperationContext,
		observation: OperationResult<String>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			context,
			model
		),
			let submission = model.composer.pendingSubmissions[context.requestID]
		else
		{
			return
		}
		if case .succeeded(let turnID) = observation, turnID == context.turnID,
			let threadID = context.threadID
		{
			acknowledge(
				submission,
				threadID: threadID,
				model: &model,
				result: &result
			)
		}
		else
		{
			model.composer.uncertainSubmissions.insert(context.requestID)
		}
	}

	private static func acknowledge(
		_ submission: ComposerSubmission,
		threadID: String,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard model.composer.acknowledgedSubmissions.insert(submission.context.requestID).inserted
		else
		{
			return
		}
		let conversation = ConversationKey.thread(threadID)
		mergeReferences(
			submission.draft.context,
			conversation: conversation,
			model: &model
		)
		var clearedDraft: ComposerDraft?
		if let draft = model.composer.drafts[conversation], draft == submission.draft
		{
			let cleared = ComposerDraft(
				revision: draft.revision + 1,
				lifetime: draft.lifetime
			)
			model.composer.drafts[conversation] = cleared
			clearedDraft = cleared
		}
		result.effects.append(.acknowledgeSubmission(SubmissionAcknowledgementWrite(
			submission: submission,
			threadID: threadID,
			draft: clearedDraft
		)))
	}

	private static func resolveUncertain(
		threadID: String?,
		attempt: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard let threadID
		else
		{
			return
		}
		for id in model.composer.uncertainSubmissions
		{
			guard model.composer.submissionConversations[id] == .thread(threadID),
					let submission = model.composer.pendingSubmissions[id]
			else
			{
				continue
			}
			mergeReferences(
				submission.draft.context,
				conversation: .thread(threadID),
				model: &model
			)
			finish(
				submission,
				attempt: attempt,
				model: &model,
				result: &result
			)
		}
	}

	private static func finish(
		_ submission: ComposerSubmission,
		attempt: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let id = submission.context.requestID
		guard model.composer.resolvingSubmissions[id] == nil
		else
		{
			return
		}
		model.composer.resolvingSubmissions[id] = attempt
		if let conversation = model.composer.submissionConversations[id],
			var draft = model.composer.drafts[conversation], draft == submission.draft
		{
			// Resolving an unacknowledged request preserves its text while retiring its snapshot.
			draft.revision += 1
			model.composer.drafts[conversation] = draft
		}
		result.effects.append(.releaseSubmission(WorkspaceSubmissionReleaseOperation(
			context: attempt,
			submission: submission
		)))
	}
}
