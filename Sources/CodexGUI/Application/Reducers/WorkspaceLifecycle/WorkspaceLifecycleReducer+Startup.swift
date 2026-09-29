import Foundation

extension WorkspaceLifecycleReducer
{
	static func reduceStartup(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceLifecycleAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .sourceStartupRequested(let context):
			guard case .source(let sessionID) = reference(model).owner,
					sessionID == model.identity.sessionID,
					model.identity.canonicalCheckoutPath == nil, valid(
					context,
					model
					)
			else
			{
				return result
			}
			model.lifecycle.pendingSourceStartup = context
			result.effects = [.restoreSourceStartup(context)]
		case .sourceStartupRestored(
			let context,
			let observation
		):
			guard model.lifecycle.pendingSourceStartup == context,
					case .source(let sessionID) = reference(model).owner,
					sessionID == context.workspace.sessionID,
					model.identity.canonicalCheckoutPath == nil, valid(
					context,
					model
					)
			else
			{
				return result
			}
			switch observation
			{
			case .failed(let failure):
				model.lifecycle.pendingSourceStartup = nil
				model.lifecycle.statusMessage = failure.message
			case .succeeded(let startup):
				if let project = startup.project
				{
					guard project.identity.sessionID == sessionID,
							project.identity.canonicalCheckoutPath != nil
					else
					{
						return result
					}
				}
				model.lifecycle.pendingSourceStartup = nil
				result = PreferenceReducer.reduce(
					&model,
					.preferences(.restored(startup.preferences))
				)
				guard let project = startup.project
				else
				{
					return result
				}
				model.identity = project.identity
				let activated = OperationContext(
					workspace: project.identity,
					generation: context.generation,
					requestID: context.requestID,
					threadID: project.selectedThreadID
				)
				let restored = WorkspaceLifecycleComposition.reduceConnectionTransition(
					&model,
					.connection(.projectRestored(
						activated,
						pendingCommands: startup.pendingCommands,
						selectedThreadID: project.selectedThreadID
					))
				)
				result.effects += [.subscribe(activated)] + restored.effects
				result.domainEvents += restored.domainEvents
				result.presentationCommands += restored.presentationCommands
			}
		case .projectPinRequested(
			let context,
			let url
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = [.normalizeProjectPreference(
				context,
				url,
				name: nil
			)]
		case .projectRenameRequested(
			let context,
			let url,
			let name
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = [.normalizeProjectPreference(
				context,
				url,
				name: name
			)]
		case .projectOpeningRequested(
			let context,
			let url
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			model.lifecycle.pendingProjectOpening = context
			result.effects = [.prepareProjectOpening(
				context,
				url
			)]
		case .projectOpeningFinished(
			let context,
			let outcome
		):
			guard valid(
				context,
				model
			), model.lifecycle.pendingProjectOpening == context
			else
			{
				return result
			}
			model.lifecycle.pendingProjectOpening = nil
			switch outcome
			{
			case .failed(let failure): model.lifecycle.statusMessage = failure.message
			case .succeeded(let opening):
				let transition = WorkspaceAction.connection(.projectOpened(
					opening.identity,
					selectedThreadID: opening
						.selectedThreadID
				))
				guard accepts(
					transition,
					model: model
				)
				else
				{
					return result
				}
				result = WorkspaceLifecycleComposition.reduceConnectionTransition(
					&model,
					transition
				)
				let remembered = PreferenceReducer.reduce(
					&model,
					.preferences(.projectRemembered(
						OperationContext(
							workspace: model.identity,
							generation: model.connection.generation,
							requestID: context.requestID
						),
						canonicalPath: opening.identity.canonicalCheckoutPath!
					))
				)
				result.effects += remembered.effects; result.domainEvents += remembered
					.domainEvents
				result.presentationCommands += remembered.presentationCommands
			}
		case .archivedSelectionRequested(
			let context,
			let archived
		):
			guard valid(
				context,
				model
			),
				model.conversations.showingArchived != archived
			else
			{
				return result
			}
			model.lifecycle.pendingArchivedSelection = context
			result.effects = [.restoreArchivedSelection(
				context,
				archived: archived
			)]
		case .archivedSelectionRestored(
			let context,
			let archived,
			let threadID
		):
			guard valid(
				context,
				model
			), model.lifecycle.pendingArchivedSelection == context
			else
			{
				return result
			}
			model.lifecycle.pendingArchivedSelection = nil
			let selected = OperationContext(
				workspace: model.identity,
				generation: context.generation,
				requestID: context.requestID,
				threadID: threadID
			)
			result = ConversationReducer.reduce(
				&model,
				.conversations(.archivedFilterRequested(
					selected,
					archived: archived
				))
			)
			let refreshed = WorkspaceLifecycleComposition.refresh(
				selected,
				model: &model
			)
			result.effects += refreshed.effects; result.domainEvents += refreshed
				.domainEvents
			result.presentationCommands += refreshed.presentationCommands
		case .initialHydrationRequested(let context):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = [.restorePreferences(context), .restoreExecution(
				context,
				selectedThreadID: model
					.conversations
					.selectedConversation
					.threadID
			)]
		case .bootstrapRequested(let context):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			model.lifecycle.bootstrapRequestID = context.requestID
			result = WorkspaceLifecycleComposition.reduceConnectionTransition(
				&model,
				.connection(.connectRequested(context))
			)
		case .refreshRequested(let context):
			guard valid(
				context,
				model
			), model.connection.isConnected
			else
			{
				return result
			}
			result = WorkspaceLifecycleComposition.refresh(
				context,
				model: &model
			)
		case .composerHydrationRequested(let context):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			result.effects = [.restoreComposer(context)]
		case .capabilityRejected(
			let context,
			let reason
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			model.lifecycle.statusMessage = reason
		case .diagnosticsReceived(
			let context,
			let diagnostics
		):
			guard valid(
				context,
				model
			)
			else
			{
				return result
			}
			model.lifecycle.backendDiagnostics = diagnostics
		case .reusableReferencesReceived(
			let operation,
			let items
		):
			guard valid(
				operation.context,
				model
			),
				operation.conversation == model.conversations.selectedConversation,
				WorkspaceSelectors(
					model: model,
					now: .distantPast
				)
				.reusableReferenceCandidates == operation.items
			else
			{
				return result
			}
			model.lifecycle.validatedReusableReferences[operation.conversation] = items
			model.lifecycle
				.validatedImagePaths = Set(items.filter
				{
					$0.kind == .image
				}
				.compactMap(\.path))
		case .shutdownRequested:
			model.lifecycle.isShutdown = true
			result = WorkspaceLifecycleComposition.reduceConnectionTransition(
				&model,
				.connection(.shutdownRequested)
			)
		default: break
		}
		return result
	}

}
