import Foundation

/// A synchronous scope reuses canonical feature transitions for the captured execution owner.
/// Scope is restored before the model leaves reduction; it is never a publication value.
@MainActor
enum WorkspaceExecutionScope
{
	private enum Target
	{
		case current
		case identity(ExecutionConversationIdentity)
		case unresolved
	}

	static func canResolve(
		action: WorkspaceAction,
		model: WorkspaceModel
	) -> Bool
	{
		if case .unresolved = target(
			for: action,
			model: model
		)
		{
			return false
		}
		return true
	}

	static func reduce(
		action: WorkspaceAction,
		model: inout WorkspaceModel,
		body: @MainActor (inout WorkspaceModel) -> WorkspaceReduction
	) -> WorkspaceReduction
	{
		let previousThreadIDs = model.executionRecoveryThreadIDs
		var result = reduce(
			target: target(
				for: action,
				model: model
			),
			model: &model,
			body: body
		)
		checkpointRecovery(
			model: model,
			previousThreadIDs: previousThreadIDs,
			result: &result
		)
		return result
	}

	static func reduce(
		event: WorkspaceDomainEvent,
		model: inout WorkspaceModel,
		body: @MainActor (inout WorkspaceModel) -> WorkspaceReduction
	) -> WorkspaceReduction
	{
		let previousThreadIDs = model.executionRecoveryThreadIDs
		let target: Target
		switch event
		{
		case .submissionAccepted(let submission): target = submissionTarget(submission)
		case .submissionPrepared(let prepared):
			target = contextTarget(
				prepared.submission.context,
				model: model
			)
		case .backendObserved(
			let event,
			_
		):
			target = backendTarget(
				event,
				model: model
			)
		case .historyAccepted(
			_,
			let threadID
		): target = .identity(.thread(threadID))
		case .completedHistoryReadRequested(let operation):
			target = contextTarget(
				operation.context,
				model: model
			)
		default: target = .current
		}
		var result = reduce(
			target: target,
			model: &model,
			body: body
		)
		checkpointRecovery(
			model: model,
			previousThreadIDs: previousThreadIDs,
			result: &result
		)
		return result
	}

	private static func checkpointRecovery(
		model: WorkspaceModel,
		previousThreadIDs: [String],
		result: inout WorkspaceReduction
	)
	{
		let currentThreadIDs = model.executionRecoveryThreadIDs
		guard previousThreadIDs != currentThreadIDs
		else
		{
			return
		}
		result.effects.removeAll
		{
			if case .persistExecutionRecovery = $0
			{
				return true
			}
			return false
		}
		// The existing workspace session scopes this synchronous local checkpoint.
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: model.identity.sessionID
		)
		result.effects.insert(
			.persistExecutionRecovery(
				context,
				currentThreadIDs
			),
			at: 0
		)
	}

	private static func reduce(
		target: Target,
		model: inout WorkspaceModel,
		body: @MainActor (inout WorkspaceModel) -> WorkspaceReduction
	) -> WorkspaceReduction
	{
		switch target
		{
		case .current:
			return model.reduceExecutionScope(
				nil,
				body: body
			)
		case .identity(let identity):
			return model.reduceExecutionScope(
				identity,
				body: body
			)
		case .unresolved:
			// Each feature still receives persistence and custom actions it can validate itself.
			return body(&model)
		}
	}

	private static func target(
		for action: WorkspaceAction,
		model: WorkspaceModel
	) -> Target
	{
		switch action
		{
		case .execution(let action):
			return executionTarget(
				action,
				model: model
			)
		case .conversations(let action):
			return conversationTarget(
				action,
				model: model
			)
		case .composerCommand(let action):
			return commandTarget(
				action,
				model: model
			)
		case .workspaceLifecycle(.inputPreparationRequested(let operation)),
				.workspaceLifecycle(.inputPreparationFinished(
				let operation,
				_
				)):
			return submissionTarget(operation.submission)
		default: return .current
		}
	}

	private static func submissionTarget(_ submission: ComposerSubmission) -> Target
	{
		switch submission.conversation
		{
		case .thread(let threadID): return .identity(.thread(threadID))
		case .newChat: return .identity(.newChat(lifetime: submission.draft.lifetime))
		}
	}

	private static func contextTarget(
		_ context: OperationContext,
		model: WorkspaceModel
	) -> Target
	{
		guard context.workspace == model.identity
		else
		{
			return .unresolved
		}
		if let identity = model.executions.identity(for: context)
		{
			return .identity(identity)
		}
		guard context.generation == model.connection.generation
		else
		{
			return .unresolved
		}
		if let threadID = context.threadID
		{
			return .identity(.thread(threadID))
		}
		return .unresolved
	}

	private static func executionTarget(
		_ action: ExecutionAction,
		model: WorkspaceModel
	) -> Target
	{
		switch action
		{
		case .submissionRequested(let submission): return submissionTarget(submission)
		case .conversationSelected(
			let threadID,
			_
		):
			return .identity(threadID.map(ExecutionConversationIdentity.thread)
				?? model.executionIdentity(for: .newChat))
		case .conversationCleared: return .identity(model.executionIdentity(for: .newChat))
		case .recoveryTargetUnavailable: return .current
		case .preparedConversationAdopted(let write):
			return contextTarget(
				write.prepared.submission.context,
				model: model
			)
		case .backendObserved(
			let context,
			let event,
			_
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return .unresolved
			}
			return backendTarget(
				event,
				model: model
			)
		case .completedHistoryRequested(let operation), .completedHistoryReceived(
			let operation,
			_
		),
		.historyObserved(
			let operation,
			_
		), .reconciliationRequested(let operation):
			return contextTarget(
				operation.context,
				model: model
			)
		case .steeringRequested(let operation), .steeringTransportFinished(
			let operation,
			_
		):
			return contextTarget(
				operation.context,
				model: model
			)
		case .interactionResponseRequested(let operation):
			return contextTarget(
				operation.context,
				model: model
			)
		case .stopRequested(
			let context,
			let ownerRequestID
		):
			if let ownerRequestID
			{
				let ownerContext = OperationContext(
					workspace: context.workspace,
					generation: context.generation,
					requestID: ownerRequestID,
					threadID: context.threadID,
					turnID: context.turnID
				)
				guard let identity = model.executions.identity(for: ownerContext)
				else
				{
					return .unresolved
				}
				return .identity(identity)
			}
			return contextTarget(
				context,
				model: model
			)
		case .preparedPersistenceFinished(
			let context,
			_
		),
		.draftAcknowledgementFinished(
			let context,
			_
		),
		.submissionPrepared(
			let context,
			_
		), .submissionAcknowledged(
			let context,
			_
		),
		.submissionCancelledBeforeSend(let context), .submissionStartFailed(
			let context,
			_,
			_
		),
		.gitTurnBaselineBindingFinished(
			let context,
			_,
			_,
			_
		),
		.gitTurnBaselineDiscarded(
			let context,
			_
		), .submissionFailed(
			let context,
			_
		),
		.steeringFinished(
			let context,
			_
		), .interruptionFinished(
			let context,
			_
		),
		.interactionResponseFinished(
			let context,
			_
		), .reconciliationFinished(
			let context,
			_
		),
		.turnStarted(
			let context,
			_
		), .turnFinished(
			let context,
			_
		),
		.commandObserved(
			let context,
			_
		), .interactionReceived(
			let context,
			_
		),
		.interactionResolved(
			let context,
			_
		), .planReceived(
			let context,
			_
		),
		.activityReceived(
			let context,
			_
		), .backendErrorReceived(
			let context,
			_
		):
			return contextTarget(
				context,
				model: model
			)
		}
	}

	private static func conversationTarget(
		_ action: ConversationsAction,
		model: WorkspaceModel
	) -> Target
	{
		let context: OperationContext
		switch action
		{
		case .historyRequested(let operation), .historyReceived(
			let operation,
			_
		):
			context = operation.context
		case .earlierTurnsRequested(let operation), .earlierTurnsReceived(
			let operation,
			_
		):
			context = operation.context
		case .turnContentsRequested(let operation), .turnContentsReceived(
			let operation,
			_,
			_,
			_
		):
			context = operation.context
		case .turnReferencesRequested(let operation), .turnReferencesReceived(
			let operation,
			_
		):
			context = operation.context
		case .lockedChatRetryRequested(let captured): context = captured
		case .selectionRequested(let captured), .selectionReceived(
			let captured,
			_
		),
		.itemStarted(
			let captured,
			_
		), .itemFinished(
			let captured,
			_
		),
		.agentMessageDelta(
			let captured,
			_
		), .commandOutputDelta(
			let captured,
			_
		),
		.fileChangesReceived(
			let captured,
			_
		), .aggregateDiffReceived(
			let captured,
			_
		):
			context = captured
		case .managementRequested(let operation): context = operation.context
		case .managementFinished(
			let captured,
			_
		): context = captured
		default: return .current
		}
		return contextTarget(
			context,
			model: model
		)
	}

	private static func commandTarget(
		_ action: ComposerCommandAction,
		model: WorkspaceModel
	) -> Target
	{
		let context: OperationContext
		switch action
		{
		case .requested(let request), .acknowledged(let request),
				.forkRecoveryRequested(
				let request,
				_
				), .forkFinished(
				let request,
				_
				):
			return .identity(model.executionIdentity(for: request.conversation))
		case .rejected(
			let captured,
			_
		): context = captured
		case .compactAcknowledged(
			let operation,
			_
		), .reviewAcknowledged(
			let operation,
			_
		):
			context = operation.request.context
		case .settingsFinished(
			let operation,
			_
		), .settingsRetryRequested(let operation):
			context = operation.request.context
		case .backendObserved(
			_,
			let event
		):
			return backendTarget(
				event,
				model: model
			)
		}
		return contextTarget(
			context,
			model: model
		)
	}

	private static func backendTarget(
		_ event: AppServerEvent,
		model: WorkspaceModel
	) -> Target
	{
		let threadID: String
		if let identity = event.turnContentIdentity
		{
			threadID = identity.threadID
		}
		else
		{
			switch event
			{
			case .planUpdated(let plan): threadID = plan.threadId
			case .interaction(let interaction): threadID = interaction.threadId
			case .interactionResolved(
				let id,
				_
			), .toolProgress(
				let id,
				_,
				_,
				_
			),
			.contextCompacted(
				let id,
				_
			), .error(
				let id,
				_,
				_,
				_
			): threadID = id
			case .threadSettingsUpdated(
				let id,
				_
			), .threadStatusChanged(
				let id,
				_
			):
				if model.executions.entries[.thread(id)] != nil
					|| model.composerCommands.pendingSettings?.request.context.threadID == id
				{
					return .identity(.thread(id))
				}
				return .current
			default: return .current
			}
		}
		guard !threadID.isEmpty,
				model.executions.entries[.thread(threadID)] != nil
				|| model.conversations.selectedConversation == .thread(threadID)
		else
		{
			return .unresolved
		}
		return .identity(.thread(threadID))
	}
}
