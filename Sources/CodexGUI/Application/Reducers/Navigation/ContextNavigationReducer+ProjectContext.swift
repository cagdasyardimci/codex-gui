import Foundation

extension ContextNavigationReducer
{
	static func reduceProjectContextIntent(
		_ action: ContextNavigationAction,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		switch action
		{
		case .contextLoadRequested(let operation):
			guard valid(
				operation.context,
				model
			), model.identity.canonicalCheckoutPath != nil,
			operation.revision == model.contextNavigation.contextRevision
			else
			{
				return
			}
			model.contextNavigation.pendingContextLoad = operation
			result.effects.append(.loadProjectContext(operation))
		case .contextReceived(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			),
				let pending = model.contextNavigation.pendingContextLoad,
				pending.context == operation.context,
				pending.revision == operation.revision
			else
			{
				return
			}
			model.contextNavigation.pendingContextLoad = nil
			guard operation.revision == model.contextNavigation.contextRevision
			else
			{
				return
			}
			switch observation
			{
			case .succeeded(let context): model.contextNavigation.projectContext = context
				model.contextNavigation.contextError = nil
			case .failed(let failure): model.contextNavigation.projectContext = ProjectContext()
				model.contextNavigation.contextError = failure.message
			}
		case .contextEdited(let operation):
			save(
				operation,
				model: &model,
				result: &result
			)
		case .contextPersistenceFinished(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			),
				let pending = model.contextNavigation.pendingContextSave,
				pending.context == operation.context,
				pending.revision == operation.revision
			else
			{
				return
			}
			model.contextNavigation.pendingContextSave = nil
			guard operation.revision == model.contextNavigation.contextRevision
			else
			{
				return
			}
			model.contextNavigation.contextError = observation.failure?.message
		case .savedPromptInserted: break
		case .bookmarkToggled(
			let context,
			let bookmark
		):
			guard valid(
				context,
				model
			)
			else
			{
				return
			}
			save(
				ContextSaveOperation(
					context: context,
					revision: model.contextNavigation.contextRevision + 1,
					value: ProjectProductivity.toggledBookmark(
						context: model.contextNavigation.projectContext,
						bookmark: bookmark
					)
				),
				model: &model,
				result: &result
			)
		case .skillsRefreshRequested(let operation):
			requestSkills(
				operation,
				model: &model,
				result: &result
			)
		case .skillsInvalidated(let context):
			guard valid(
				context,
				model
			), model.identity.canonicalCheckoutPath != nil
			else
			{
				return
			}
			requestSkills(
				SkillsRefreshOperation(
					context: context,
					attempt: 0
				),
				model: &model,
				result: &result
			)
		case .skillsReceived(
			let operation,
			let observation
		):
			guard valid(
				operation.context,
				model
			),
				let pending = model.contextNavigation.pendingSkillRefresh,
				pending.context == operation.context,
				pending.attempt == operation.attempt
			else
			{
				return
			}
			let shouldRefreshAgain = model.contextNavigation.skillRefreshPending
				&& operation.attempt == 0
			model.contextNavigation.pendingSkillRefresh = nil
			model.contextNavigation.skillRefreshPending = false
			switch observation
			{
			case .succeeded(let catalog): model.contextNavigation.skillCatalog = catalog
				model.contextNavigation.skillError = catalog.errors.isEmpty ? nil :
					catalog.errors.map
					{
						"\($0.path): \($0.message)"
					}.joined(separator: "\n")
			case .failed(let failure): model.contextNavigation.skillCatalog = nil
				model.contextNavigation.skillError = "Skills unavailable: \(failure.message)"
			}
			if shouldRefreshAgain
			{
				requestSkills(
					SkillsRefreshOperation(
						context: operation.context,
						attempt: 1
					),
					model: &model,
					result: &result
				)
			}
		default: break
		}
	}

	static func savedPromptDraftAction(
		context: OperationContext,
		promptID: String,
		model: WorkspaceModel
	) -> WorkspaceAction?
	{
		guard valid(
			context,
			model
		), selected(
			context,
			model
		),
			let text = ProjectProductivity.insertSavedPrompt(
				context: model.contextNavigation.projectContext,
				id: promptID,
				into: (model.composer
					.drafts[model.conversations.selectedConversation] ?? ComposerDraft()).text
			)
		else
		{
			return nil
		}
		let key = model.conversations.selectedConversation
		let revision = (model.composer.drafts[key] ?? ComposerDraft()).revision + 1
		return .composer(.draftEdited(
			context,
			conversation: key,
			text: text,
			revision: revision
		))
	}

	private static func save(
		_ operation: ContextSaveOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		),
			operation.revision > model.contextNavigation.contextRevision
		else
		{
			return
		}
		model.contextNavigation.projectContext = operation.value
		model.contextNavigation.contextRevision = operation.revision
		model.contextNavigation.contextError = nil
		guard model.identity.canonicalCheckoutPath != nil
		else
		{
			model.contextNavigation
				.contextError = "Open a project before saving project context."
			return
		}
		model.contextNavigation.pendingContextSave = operation
		result.effects.append(.saveProjectContext(operation))
	}

	private static func requestSkills(
		_ operation: SkillsRefreshOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			operation.context,
			model
		), model.identity.canonicalCheckoutPath != nil,
		model.connection.isConnected, (0 ... 1).contains(operation.attempt)
		else
		{
			return
		}
		if model.contextNavigation.pendingSkillRefresh != nil
		{
			model.contextNavigation.skillRefreshPending = true
			return
		}
		model.contextNavigation.pendingSkillRefresh = operation
		result.effects.append(.readSkills(operation))
	}

}
