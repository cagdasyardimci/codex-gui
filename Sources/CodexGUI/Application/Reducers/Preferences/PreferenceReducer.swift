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
				model.preferences.pendingSignOut = nil
				model.preferences.signOutError = nil
				model.preferences.accountStatus = nil
				model.preferences.statusMessage = nil
			}
			return result
		}
		switch action
		{
		case .restored, .modelSelected, .effortSelected, .approvalModeSelected,
				.configurationDefaultsApplied, .fastModeSelected, .taskPinToggled,
				.projectPinToggled, .projectRenamed,
				.projectRemembered, .projectRemoved:
			result = reducePreferenceChanges(
				action,
				model: &model
			)
		case .accountRefreshRequested, .modelsRefreshRequested, .signInRequested,
				.modelsReceived, .accountReceived, .signInURLReceived, .signOutRequested,
				.signOutFinished:
			result = reduceAccountAndCatalog(
				action,
				model: &model
			)
		case .persistenceFinished(
			let context,
			let observation
		):
			finishPreferencePersistence(
				context: context,
				observation: observation,
				model: &model
			)
		}

		registerPreferenceWrites(
			in: result.effects,
			model: &model
		)
		return result
	}

	private static func reducePreferenceChanges(
		_ action: PreferencesAction,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .restored(let value):
			model.preferences.globalModelPreference = value.modelPreference
			model.preferences.runPreferences = value.runPreferences
			model.preferences.recentProjects = value.recentProjects
			model.preferences.pinnedProjectPaths = value.pinnedProjectPaths
			model.preferences.removedProjectPaths = value.removedProjectPaths
			model.preferences.pinnedTasks = value.pinnedTasks
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
			let current = model.composerSelection
			let preference = ProjectModelPreference(
				modelID: id,
				effort: nil
			)
			result = select(
				preference,
				context: context,
				model: &model
			)
			model.recordLocalComposerSelection(ComposerSelection(
				modelID: id,
				effort: nil,
				fastMode: current.fastMode
			))
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
			let current = model.composerSelection
			let preference = ProjectModelPreference(
				modelID: current.modelID,
				effort: effort
			)
			result = select(
				preference,
				context: context,
				model: &model
			)
			model.recordLocalComposerSelection(ComposerSelection(
				modelID: current.modelID,
				effort: effort,
				fastMode: current.fastMode
			))
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
			var defaults = model.preferences.runPreferences.configurationDefaults
			defaults?.approvalPolicy = nil
			defaults?.sandboxMode = nil
			defaults?.networkAccess = nil
			model.preferences.runPreferences = RunPreferences(
				approvalMode: mode,
				fastMode: model.preferences.runPreferences.fastMode,
				configurationDefaults: defaults?.isEmpty == false ? defaults : nil
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
			let current = model.composerSelection
			if enabled, let reason = FastModeAvailability.unavailableReason(in: model)
			{
				model.preferences.statusMessage = reason
				return result
			}
			model.preferences.statusMessage = nil
			var defaults = model.preferences.runPreferences.configurationDefaults
			defaults?.serviceTier = nil
			model.preferences.runPreferences = RunPreferences(
				approvalMode: model.preferences.runPreferences.approvalMode,
				fastMode: enabled,
				configurationDefaults: defaults?.isEmpty == false ? defaults : nil
			)
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .run(model.preferences
					.runPreferences)
			))]
			model.recordLocalComposerSelection(ComposerSelection(
				modelID: current.modelID,
				effort: current.effort,
				fastMode: enabled
			))
		case .configurationDefaultsApplied(
			let context,
			let update
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			var defaults = model.preferences.runPreferences.configurationDefaults
				?? RunConfigurationDefaults()
			defaults.apply(update)
			let current = model.composerSelection
			model.preferences.runPreferences = RunPreferences(
				approvalMode: model.preferences.runPreferences.approvalMode,
				fastMode: current.fastMode,
				configurationDefaults: defaults.isEmpty ? nil : defaults
			)
			if update.keys.contains(.serviceTier)
			{
				model.recordLocalComposerSelection(ComposerSelection(
					modelID: current.modelID,
					effort: current.effort,
					fastMode: model.preferences.runPreferences.fastMode
				))
			}
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .run(model.preferences.runPreferences)
			))]

		case .taskPinToggled(
			let context,
			let task
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			)
			else
			{
				return result
			}
			let pinned = !model.preferences.pinnedTasks.contains
			{
				$0.id == task.id
			}
			model.preferences.pinnedTasks.removeAll
			{
				$0.id == task.id
			}
			if pinned
			{
				model.preferences.pinnedTasks.append(task)
			}
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .taskPin(
					task,
					pinned: pinned
				)
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
		case .projectRemoved(
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
			model.preferences.removedProjectPaths.insert(path)
			model.preferences.pinnedProjectPaths.remove(path)
			model.preferences.recentProjects.removeAll
			{
				$0.path == path
			}
			result.effects = [.persistPreference(PreferenceWrite(
				context: context,
				value: .removeProject(path: path)
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
		default: break
		}
		return result
	}

	private static func reduceAccountAndCatalog(
		_ action: PreferencesAction,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
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
		case .signOutRequested(let context):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				model.connection.isConnected, model.preferences.pendingSignOut == nil,
				model.preferences.accountStatus?.type != nil
			else
			{
				return result
			}
			model.preferences.signOutError = nil
			model.preferences.pendingSignOut = context
			result.effects = [.signOut(context)]
		case .signOutFinished(
			let context,
			let observation
		):
			guard PreferenceScope.accepts(
				context,
				model: model
			),
				model.preferences.pendingSignOut == context
			else
			{
				return result
			}
			model.preferences.pendingSignOut = nil
			switch observation
			{
			case .succeeded:
				model.preferences.accountStatus = nil
				model.preferences.accountDescription = "Sign in required"
				model.preferences.statusMessage = "Logged out of Codex."
				result.domainEvents = [.accountSignedOut]
				model.preferences.pendingAccount = context
				result.effects = [.readAccount(context)]
			case .failed(let failure):
				model.preferences.signOutError = failure.message
				model.preferences.statusMessage = "Could not log out: \(failure.message)"
			}
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
			case .succeeded(let account):
				model.preferences.accountDescription = account.description
				model.preferences.accountStatus = account
			case .failed(let failure):
				model.preferences.accountStatus = nil
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
		default: break
		}
		return result
	}

	private static func finishPreferencePersistence(
		context: OperationContext,
		observation: OperationResult<Void>,
		model: inout WorkspaceModel
	)
	{
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
			return
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

	private static func registerPreferenceWrites(
		in effects: [WorkspaceEffect],
		model: inout WorkspaceModel
	)
	{
		for effect in effects
		{
			if case .persistPreference(let write) = effect
			{
				model.preferences.pendingPreferenceWrites[write.key] = write.context
			}
		}
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
