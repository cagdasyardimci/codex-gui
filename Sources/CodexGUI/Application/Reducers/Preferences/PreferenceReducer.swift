import Foundation

@MainActor
enum PreferenceReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	)
		-> WorkspaceReduction
	{
		synchronize(&model)
		var result = WorkspaceReduction()
		guard case .preferences(let action) = action
		else
		{
			if case .connection(.connectRequested(let context)) = action,
				model.connection.pendingConnection?.requestID == context.requestID
			{
				model.preferences.models = []
				model.preferences.modelListError = nil
				model.preferences.pendingModels = nil
				model.preferences.pendingAccount = nil
				model.preferences.pendingSignIn = nil
				model.preferences.statusMessage = nil
			}
			return result
		}
		switch action
		{
		case .restored(let value):
			model.preferences.globalModelPreference = value.modelPreference
			model.preferences.runPreferences = value.runPreferences
			model.preferences.recentProjects = value.recentProjects
			model.preferences.pinnedProjectPaths = value.pinnedProjectPaths
			model.preferences.projectDisplayNames = value.projectDisplayNames
			model.preferences.resolveSelection()
		case .modelSelected(
			let context,
			let id
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			let preference = ProjectModelPreference(
				modelID: id,
				effort: nil
			)
			result = select(
				preference,
				context: context,
				model: &model
			)
		case .effortSelected(
			let context,
			let effort
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			let preference = ProjectModelPreference(
				modelID: model.preferences.selectedModelID,
				effort: effort
			)
			result = select(
				preference,
				context: context,
				model: &model
			)
		case .approvalModeSelected(
			let context,
			let mode
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			model.preferences.runPreferences = RunPreferences(
				approvalMode: mode,
				fastMode: model.preferences
					.runPreferences.fastMode
			)
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .run(model.preferences
					.runPreferences)
			))]
		case .fastModeSelected(
			let context,
			let enabled
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			model.preferences.runPreferences = RunPreferences(
				approvalMode: model.preferences.runPreferences.approvalMode,
				fastMode: enabled
			)
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .run(model.preferences
					.runPreferences)
			))]
		case .projectPinToggled(
			let context,
			let path
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			let pinned = !model.preferences.pinnedProjectPaths.contains(path)
			if pinned
			{
				model.preferences.pinnedProjectPaths.insert(path)
			}
			else
			{
				model.preferences.pinnedProjectPaths.remove(path)
			}
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .pin(
					path: path,
					pinned: pinned
				)
			))]
		case .projectRenamed(
			let context,
			let path,
			let name
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
			model.preferences.projectDisplayNames[path] = trimmed.isEmpty ? nil : trimmed
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .name(
					path: path,
					name: trimmed
				)
			))]
		case .projectRemembered(
			let context,
			let path
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .recent(path: path)
			))]
		case .accountRefreshRequested(let context):
			guard PreferenceScope.accepts(
				context,
				model: model
			), model.connection.isConnected
			else
			{
				return result
			}
			model.preferences.pendingAccount = context
			result.effects = [.readAccount(context)]
		case .modelsRefreshRequested(let context):
			guard PreferenceScope.accepts(
				context,
				model: model
			), model.connection.isConnected
			else
			{
				return result
			}
			model.preferences.pendingModels = context
			result.effects = [.readModels(context)]
		case .signInRequested(let context):
			guard PreferenceScope.accepts(
				context,
				model: model
			), model.connection.isConnected
			else
			{
				return result
			}
			model.preferences.pendingSignIn = context
			result.effects = [.beginSignIn(context)]
		case .modelsReceived(
			let context,
			let observation
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				model.preferences.pendingModels == context
			else
			{
				return result
			}
			model.preferences.pendingModels = nil
			switch observation
			{
			case .succeeded(let models):
				model.preferences.models = models
				model.preferences.modelListError = nil
				model.preferences.resolveSelection()
			case .failed(let failure):
				model.preferences.modelListError = "Model list unavailable: \(failure.message)"
			}
		case .accountReceived(
			let context,
			let observation
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				model.preferences.pendingAccount == context
			else
			{
				return result
			}
			model.preferences.pendingAccount = nil
			switch observation
			{
			case .succeeded(let account): model.preferences.accountDescription = account.description
			case .failed(let failure):
				model.preferences.accountDescription = "Could not check sign-in: \(failure.message)"
			}
		case .signInURLReceived(
			let context,
			let observation
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				model.preferences.pendingSignIn == context
			else
			{
				return result
			}
			model.preferences.pendingSignIn = nil
			switch observation
			{
			case .succeeded(let url):
				model.preferences.statusMessage = "Continue signing in through your browser."
				result.presentationCommands = [.openSignIn(url)]
			case .failed(let failure):
				model.preferences.statusMessage = "Could not start sign-in: \(failure.message)"
			}
		case .persistenceFinished(
			let context,
			let observation
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				let key = model.preferences.pendingPreferenceWrites
				.first(where:
					{
						$0.value == context
					})?.key
			else
			{
				return result
			}
			model.preferences.pendingPreferenceWrites.removeValue(forKey: key)
			if case .failed(let failure) = observation
			{
				model.preferences.preferenceWriteErrors[key] = failure.message
			}
			else
			{
				model.preferences.preferenceWriteErrors.removeValue(forKey: key)
			}
			model.preferences.persistenceError = model.preferences.preferenceWriteErrors.values
				.sorted().first
		}
		for effect in result.effects
		{
			if case .persistPreference(let write) = effect
			{
				model.preferences.pendingPreferenceWrites[write.key] = write.context
			}
		}
		return result
	}
	static func synchronize(_ model: inout WorkspaceModel)
	{
		model.preferences.projectModelPreference = model.contextNavigation.projectContext
			.modelPreference
		model.preferences.resolveSelection()
	}

	private static func select(
		_ preference: ProjectModelPreference,
		context: OperationContext,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		if model.contextNavigation.projectContext.modelPreference != nil
		{
			var value = model.contextNavigation.projectContext
			value.modelPreference = preference
			let result = ContextNavigationReducer.reduce(
				&model,
				.contextNavigation(.contextEdited(ContextSaveOperation(
					context: context,
					revision: model.contextNavigation
						.contextRevision + 1,
					value: value
				)))
			)
			synchronize(&model)
			return result
		}
		model.preferences.globalModelPreference = preference
		model.preferences.resolveSelection()
		return WorkspaceReduction(effects: [.persistPreference(PreferenceWrite(
			context: context,
			value: .model(preference)
		))])
	}

}
