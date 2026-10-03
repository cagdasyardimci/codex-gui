import Foundation

@MainActor
enum WorkspaceLifecycleComposition
{
	static func reduceFeatureCompletion(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .execution(.draftAcknowledgementFinished(
			let context,
			_
		)):
			guard WorkspaceLifecycleReducer.valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = referenceValidation(
				context,
				model: &model,
				force: true
			)
		case .composer(.submissionReleaseFinished(
			let operation,
			_
		)):
			guard WorkspaceLifecycleReducer.valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
			result.effects = referenceValidation(
				operation.context,
				model: &model
			)
		case .composer(.conversationRestored(
			let context,
			_,
			_,
			_
		)):
			guard WorkspaceLifecycleReducer.valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = referenceValidation(
				context,
				model: &model,
				force: true
			)
		case .connection(.connectionFinished(
			let context,
			let observation
		)):
			guard context.requestID == model.lifecycle.bootstrapRequestID,
					case .succeeded = observation,
					context.workspace.sessionID == model.identity.sessionID,
					context.generation == model.connection.generation, model.connection.isConnected
			else
			{
				return result
			}
			model.lifecycle.bootstrapRequestID = nil
			let followup = OperationContext(
				workspace: model.identity,
				generation: context.generation,
				requestID: context.requestID,
				threadID: model.conversations.selectedConversation.threadID
			)
			result = refresh(
				followup,
				model: &model
			)
		case .contextNavigation(.contextPersistenceFinished(
			let operation,
			let outcome
		)):
			guard WorkspaceLifecycleReducer.valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
			recordWrite(
				"context:" + (operation.context.workspace.canonicalCheckoutPath ?? ""),
				revision: operation.revision,
				outcome: outcome,
				model: &model
			)
		case .review(.markerPersistenceFinished(
			let operation,
			let outcome
		)):
			guard WorkspaceLifecycleReducer.valid(
				operation.context,
				model
			)
			else
			{
				return result
			}
			let reference = operation.identity.reference
			let key = ["review",
						operation.context.workspace.canonicalCheckoutPath ?? "",
						reference.threadID,
						reference.turnID,
						reference.path,
						reference.hunkID ?? ""]
				.joined(separator: "\u{0}")
			recordWrite(
				key,
				revision: operation.markerRevision,
				outcome: outcome,
				model: &model
			)
		case .execution(.submissionPrepared(
			let context,
			let observation
		)):
			guard WorkspaceLifecycleReducer.valid(
				context,
				model
			), case .succeeded(let prepared) = observation,
			let bound = prepared.workspace, let current = model.lifecycle.managedWorkspace,
			case .managed(
				let id,
				_
			) = WorkspaceLifecycleReducer.reference(model).owner,
			id == current.id, bound.hasSameOwnership(as: current),
			bound.phase == .active, bound.threadID == prepared.thread.summary.id,
			current.threadID == nil || current.threadID == bound.threadID,
			model.composer.pendingSubmissions[context.requestID]?.context
			.isSameRequest(as: context) == true
			else
			{
				return result
			}
			model.lifecycle.managedWorkspace = bound
		default: break
		}
		return result
	}

	static func persistenceFailure(_ model: WorkspaceModel) -> String?
	{
		model.composer.persistenceError ?? model.preferences.persistenceError
			?? model.lifecycle.persistenceFailures.values.first?.message
	}

	private static func recordWrite(
		_ key: String,
		revision: Int,
		outcome: OperationResult<Void>,
		model: inout WorkspaceModel
	)
	{
		switch outcome
		{
		case .failed(let failure):
			guard revision >= model.lifecycle.successfulWriteRevisions[key, default: -1],
					revision >= (model.lifecycle.persistenceFailures[key]?.revision ?? -1)
			else
			{
				return
			}
			model.lifecycle.persistenceFailures[key] = WorkspaceLifecyclePersistenceFailure(
				revision: revision,
				message: failure.message
			)
		case .succeeded:
			model.lifecycle.successfulWriteRevisions[key] = max(
				revision,
				model.lifecycle
					.successfulWriteRevisions[
						key,
						default: -1
					]
			)
			if let failure = model.lifecycle.persistenceFailures[key], failure.revision <= revision
			{
				model.lifecycle.persistenceFailures.removeValue(forKey: key)
			}
		}
	}

	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent,
		context: OperationContext
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()

		switch event
		{
		case .connectionBegan, .connectionDisconnected, .projectRestored, .submissionAccepted,
				.historyAccepted, .conversationContentChanged, .conversationSelectionChanged:
			model.lifecycle.statusMessage = nil
		default: break
		}
		switch event
		{
		case .connectionBegan, .connectionDisconnected:
			model.lifecycle.pendingSourceStartup = nil
		case .projectRestored:
			model.lifecycle.validatedReusableReferences = [:]
			model.lifecycle.validatedImagePaths = []
			model.lifecycle.referenceValidationCandidates = [:]
			result.effects = [.restoreComposer(context), .readBackendDiagnostics(context)]
			let load = ContextNavigationReducer.reduce(
				&model,
				.contextNavigation(.contextLoadRequested(
					ContextLoadOperation(
						context: context,
						revision: model.contextNavigation.contextRevision
					)
				))
			)
			result.effects += load.effects
			if model.connection.isConnected
			{
				let refreshed = refresh(
					context,
					model: &model
				)
				result.effects += refreshed.effects
				result.domainEvents += refreshed.domainEvents
				result.presentationCommands += refreshed.presentationCommands
			}
		case .conversationSelectionChanged:
			model.lifecycle.recoveryListRequestID = nil
			result.effects = [.restoreComposer(context)]
		case .conversationListAccepted(let operation):
			guard model.lifecycle.recoveryListRequestID == operation.context.requestID,
					model.execution.needsReconciliation,
					let threadID = model.execution.activeThreadID ?? model.conversations
					.selectedConversation.threadID
			else
			{
				return result
			}
			model.lifecycle.recoveryListRequestID = nil
			let selected = model.conversations.selectedConversation.threadID
			guard !model.conversations.pendingReads.values.contains(where:
				{
					$0.purpose == .selection && $0.context.threadID == selected
				})
			else
			{
				return result
			}
			let read = OperationContext(
				workspace: model.identity,
				generation: operation.context.generation,
				requestID: operation.context.requestID,
				threadID: threadID
			)
			result = ConversationReducer.reduce(
				&model,
				.conversations(.historyRequested(
					ConversationReadOperation(
						context: read,
						commandRevision: model.execution.commandEventRevisions[
							threadID,
							default: 0
						],
						purpose: .recovery,
						contentRevision: model.conversations.contentRevisions[
							threadID,
							default: 0
						]
					)
				))
			)
		case .completedHistoryRefreshed:
			let list = ConversationReducer.reduce(
				&model,
				.conversations(.threadListRequested(
					ConversationListOperation(
						context: context,
						archived: model.conversations.showingArchived,
						boundThreadID: model.lifecycle.managedWorkspace?.threadID
					)
				))
			)
			result = list
		case .conversationContentChanged:
			result.effects = referenceValidation(
				context,
				model: &model
			)
		default: break
		}
		return result
	}

	static func referenceValidation(
		_ context: OperationContext,
		model: inout WorkspaceModel,
		force: Bool = false
	) -> [WorkspaceEffect]
	{
		let key = model.conversations.selectedConversation
		let items = WorkspaceSelectors(
			model: model,
			now: .distantPast
		).reusableReferenceCandidates
		guard force || model.lifecycle.referenceValidationCandidates[key] != items
		else
		{
			return []
		}
		model.lifecycle.referenceValidationCandidates[key] = items
		let revision = key.threadID
			.map
			{
				model.conversations.contentRevisions[$0, default: 0]
			} ?? 0
		return [.validateReusableReferences(ReusableReferenceValidationOperation(
			context: context,
			conversation: key,
			revision: revision,
			items: items
		))]
	}

	static func reduceConnectionTransition(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = ConnectionReducer.reduce(
			&model,
			action
		)
		let reducers = [
			WorkspaceFeatureComposition.reducer,
			PreferenceReducer.reducer,
			UsageReducer.reducer
		]
		for reducer in reducers
		{
			let reduction = reducer.reduce(
				&model,
				action
			)
			result.effects += reduction.effects
			result.domainEvents += reduction.domainEvents
			result.presentationCommands += reduction.presentationCommands
		}
		return result
	}

	static func refresh(
		_ context: OperationContext,
		model: inout WorkspaceModel
	)
		-> WorkspaceReduction
	{
		var result = WorkspaceReduction(effects: [.readBackendDiagnostics(context)])
		result.effects += referenceValidation(
			context,
			model: &model,
			force: true
		)
		refreshAccountData(
			context,
			model: &model,
			result: &result
		)
		refreshProjectData(
			context,
			model: &model,
			result: &result
		)
		return result
	}

	private static func refreshAccountData(
		_ context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let actions: [WorkspaceAction] = [
			.preferences(.accountRefreshRequested(context)),
			.preferences(.modelsRefreshRequested(context)),
			.usage(.refreshRequested(context)),
		]
		for action in actions
		{
			let reduction: WorkspaceReduction
			if case .usage = action
			{
				reduction = UsageReducer.reduce(
					&model,
					action
				)
			}
			else
			{
				reduction = PreferenceReducer.reduce(
					&model,
					action
				)
			}
			result.effects += reduction.effects
			result.domainEvents += reduction.domainEvents
			result.presentationCommands += reduction.presentationCommands
		}
	}

	private static func refreshProjectData(
		_ context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		if model.identity.canonicalCheckoutPath != nil
		{
			model.lifecycle.recoveryListRequestID = context.requestID
			let list = ConversationReducer.reduce(
				&model,
				.conversations(.threadListRequested(
					ConversationListOperation(
						context: context,
						archived: model.conversations.showingArchived,
						boundThreadID: model.lifecycle.managedWorkspace?
							.threadID
					)
				))
			)
			result.effects += list.effects
			result.domainEvents += list.domainEvents
			result.presentationCommands += list.presentationCommands
			let skills = ContextNavigationReducer.reduce(
				&model,
				.contextNavigation(
					.skillsRefreshRequested(SkillsRefreshOperation(
						context: context,
						attempt: 0
					))
				)
			)
			result.effects += skills.effects
			result.domainEvents += skills.domainEvents
			result.presentationCommands += skills.presentationCommands
		}
	}

}
