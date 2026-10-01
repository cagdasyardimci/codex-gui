import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite("Preference scope and precedence")
struct PreferenceReducerTests
{
	@Test func absentPreferenceUsesCatalogDefaultButExplicitNilPreservesBackendDefault()
	{
		var model = fixture()
		model.preferences.models = [option(
			"default",
			efforts: ["medium"],
			isDefault: true
		)]
		model.preferences.resolveSelection()
		#expect(model.preferences.selectedModelID == "default")
		#expect(!model.preferences.hasStoredModelPreference)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				context(model),
				nil
			))
		)
		#expect(model.preferences.selectedModelID == nil)
		#expect(model.preferences.hasStoredModelPreference)
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: "global",
			effort: "high"
		)
		model.contextNavigation.projectContext.modelPreference = ProjectModelPreference(
			modelID: nil,
			effort: "medium"
		)
		PreferenceReducer.synchronize(&model)
		#expect(model.preferences.selectedModelID == nil)
		#expect(model.preferences.selectedEffort == "medium")
		#expect(model.preferences.warning(skillWarning: nil) == nil)
		model.contextNavigation.projectContext.modelPreference = nil
		PreferenceReducer.synchronize(&model)
		#expect(model.preferences.selectedModelID == "global")
		#expect(model.preferences.selectedEffort == "high")
	}

	@Test func modelChangesClearEffortAndCapturedWritesKeepTheirOriginalValue()
	{
		var model = fixture()
		let first = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				first,
				"first"
			))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.effortSelected(
				context(model),
				"high"
			))
		)
		let reduced = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				context(model),
				"second"
			))
		)
		#expect(model.preferences.selectedEffort == nil)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.effortSelected(
				context(model),
				"low"
			))
		)
		guard case .persistPreference(let write) = reduced.effects.first,
				case .model(let value) = write.value
		else
		{
			Issue.record("Expected captured model write")
			return
		}
		#expect(value.modelID == "second")
		#expect(value.effort == nil)
	}

	@Test func warningOrderIsCatalogSkillModelThenEffort()
	{
		var model = fixture()
		model.preferences.models = [option(
			"default",
			efforts: ["medium"],
			isDefault: true
		)]
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: "missing",
			effort: "high"
		)
		model.preferences.resolveSelection()
		model.preferences.modelListError = "catalog failed"
		#expect(model.preferences
			.warning(skillWarning: "skill failed") == "catalog failed Reconnect before sending.")
		model.preferences.modelListError = nil
		#expect(model.preferences.warning(skillWarning: "skill failed") == "skill failed")
		#expect(model.preferences.warning(skillWarning: nil)?
			.contains("Saved model missing") == true)
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: nil,
			effort: "high"
		)
		model.preferences.resolveSelection()
		#expect(model.preferences.warning(skillWarning: nil)?
			.contains("Saved reasoning effort high") == true)
	}

	@Test func accountCatalogBindingAcceptsSourceSelectionButRejectsRetiredGeneration()
	{
		var model = fixture(path: nil)
		let source = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelsRefreshRequested(source))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.accountRefreshRequested(source))
		)
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/project"
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelsReceived(
				source,
				.succeeded([option(
					"default",
					efforts: ["medium"],
					isDefault: true
				)])
			))
		)
		#expect(model.preferences.models.map(\.id) == ["default"])
		model.connection.generation += 1
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.accountReceived(
				source,
				.succeeded(AccountStatus(
					type: "apiKey",
					email: nil,
					requiresOpenAIAuth: false
				))
			))
		)
		#expect(model.preferences.accountDescription == "Checking sign-in…")
		let effect = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				source,
				"stale"
			))
		)
		#expect(effect.effects.isEmpty)
		#expect(model.preferences.selectedModelID == "default")
	}

	@Test func replacedCatalogRequestCannotOverrideNewerResult()
	{
		var model = fixture()
		let old = context(model)
		let newer = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelsRefreshRequested(old))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelsRefreshRequested(newer))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.modelsReceived(
				old,
				.failed(OperationFailure(
					message: "old failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.preferences.modelListError == nil)
		#expect(model.preferences.pendingModels == newer)
	}

	@Test func sharedStoresObserveGlobalWritesBeforeNextInputAndHydrateNewStores() async
	{
		let defaults = UserDefaults(suiteName: "PreferenceTests.\(UUID())")!
		let storage = LocalStorage(defaults: defaults)
		let fastModel = ModelOption(json: [
			"model": "fast-capable",
			"isDefault": true,
			"serviceTiers": [["id": "express", "name": "Fast", "description": "Fixture fast tier"]],
		])!
		let firstStore = store(
			storage,
			models: [fastModel]
		)
		let secondStore = store(
			storage,
			models: [fastModel]
		)
		firstStore.dispatch(.preferences(.approvalModeSelected(
			firstStore.operationContext(),
			.fullAccess
		)))
		#expect(secondStore.model.preferences.runPreferences.approvalMode == .fullAccess)
		secondStore.dispatch(.preferences(.fastModeSelected(
			secondStore.operationContext(),
			true
		)))
		#expect(firstStore.model.preferences.runPreferences == RunPreferences(
			approvalMode: .fullAccess,
			fastMode: true
		))
		firstStore.dispatch(.preferences(.projectPinToggled(
			firstStore.operationContext(),
			canonicalPath: "/project"
		)))
		#expect(secondStore.model.preferences.pinnedProjectPaths.contains("/project"))
		secondStore.dispatch(.preferences(.projectRenamed(
			secondStore.operationContext(),
			canonicalPath: "/project",
			name: " Local "
		)))
		#expect(firstStore.model.preferences.projectDisplayNames["/project"] == "Local")
		firstStore.dispatch(.preferences(.modelSelected(
			firstStore.operationContext(),
			nil
		)))
		let hydratedStore = store(
			storage,
			models: [fastModel]
		)
		#expect(hydratedStore.model.preferences.runPreferences == RunPreferences(
			approvalMode: .fullAccess,
			fastMode: true
		))
		#expect(hydratedStore.model.preferences.hasStoredModelPreference)
		#expect(hydratedStore.model.preferences.selectedModelID == nil)
		#expect(defaults.dictionary(forKey: "CodexGUI.modelPreference") as? [String: String] == [
			"model": "",
			"effort": ""
		])
		#expect(hydratedStore.model.preferences.recentProjects
			.contains(URL(fileURLWithPath: "/project")))
		firstStore.shutdown()
		secondStore.shutdown()
		hydratedStore.shutdown()
	}

	@Test func supersededPersistenceFailureCannotReplaceLatestSuccess()
	{
		var model = fixture()
		let old = context(model)
		let latest = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.fastModeSelected(
				old,
				true
			))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.fastModeSelected(
				latest,
				false
			))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.persistenceFinished(
				latest,
				.succeeded(())
			))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.persistenceFinished(
				old,
				.failed(OperationFailure(
					message: "retired write",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.preferences.persistenceError == nil)
		#expect(!model.preferences.runPreferences.fastMode)
	}

	@Test func signInResultProducesPresentationCommandOnlyForAcceptedRequest()
	{
		var model = fixture()
		let old = context(model)
		let latest = context(model)
		let url = URL(string: "https://example.com/sign-in")!
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signInRequested(old))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signInRequested(latest))
		)
		let retired = PreferenceReducer.reduce(
			&model,
			.preferences(.signInURLReceived(
				old,
				.succeeded(url)
			))
		)
		#expect(retired.presentationCommands.isEmpty)
		let accepted = PreferenceReducer.reduce(
			&model,
			.preferences(.signInURLReceived(
				latest,
				.succeeded(url)
			))
		)
		guard case .openSignIn(let commandURL) = accepted.presentationCommands.first
		else
		{
			Issue.record("Expected typed sign-in presentation command")
			return
		}
		#expect(commandURL == url)
		#expect(model.preferences.statusMessage == "Continue signing in through your browser.")
	}

	@Test func projectModelAndEffortIntentsComposeCanonicalCapturedContextWrites()
	{
		var model = fixture()
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: "global",
			effort: "low"
		)
		model.contextNavigation.projectContext.modelPreference = ProjectModelPreference(
			modelID: "project",
			effort: "high"
		)
		model.contextNavigation.contextRevision = 4
		let captured = context(model)
		let selected = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				captured,
				"next"
			))
		)
		#expect(model.contextNavigation.contextRevision == 5)
		#expect(model.contextNavigation.projectContext.modelPreference?.modelID == "next")
		#expect(model.preferences.selectedEffort == nil)
		#expect(model.preferences.globalModelPreference?.modelID == "global")
		guard case .saveProjectContext(let write) = selected.effects.first
		else
		{
			Issue.record("Expected canonical project context save")
			return
		}
		#expect(write.context == captured)
		#expect(write.revision == 5)
		#expect(write.value.modelPreference?.effort == nil)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.effortSelected(
				context(model),
				"medium"
			))
		)
		#expect(model.contextNavigation.contextRevision == 6)
		#expect(model.contextNavigation.projectContext.modelPreference?.effort == "medium")
		#expect(write.value.modelPreference?.effort == nil)
		#expect(model.preferences.globalModelPreference?.effort == "low")
	}

	@Test func modelIntentFromAnotherCheckoutCannotEditProjectOrGlobalPreference()
	{
		var model = fixture()
		model.contextNavigation.projectContext.modelPreference = ProjectModelPreference(
			modelID: "project",
			effort: "high"
		)
		let stale = OperationContext(
			workspace: WorkspaceIdentity(
				sessionID: model.identity.sessionID,
				canonicalCheckoutPath: "/other"
			),
			generation: model.connection.generation,
			requestID: UUID()
		)
		let result = PreferenceReducer.reduce(
			&model,
			.preferences(.modelSelected(
				stale,
				"stale"
			))
		)
		#expect(result.effects.isEmpty)
		#expect(model.contextNavigation.contextRevision == 0)
		#expect(model.preferences.selectedModelID == "project")
		#expect(model.preferences.globalModelPreference == nil)
	}

	@Test func canonicalContextLoadAndEditResolveSelectionWithoutAdapterWrites()
	{
		var model = fixture()
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: "global",
			effort: "low"
		)
		let load = ContextLoadOperation(
			context: context(model),
			revision: 0
		)
		model.contextNavigation.pendingContextLoad = load
		var project = ProjectContext()
		project.modelPreference = ProjectModelPreference(
			modelID: "project",
			effort: "high"
		)
		let received = WorkspaceAction.contextNavigation(.contextReceived(
			load,
			.succeeded(project)
		))
		_ = ContextNavigationReducer.reduce(
			&model,
			received
		)
		_ = PreferenceReducer.reduce(
			&model,
			received
		)
		#expect(model.preferences.selectedModelID == "project")
		project.modelPreference = nil
		let edit = WorkspaceAction.contextNavigation(.contextEdited(ContextSaveOperation(
			context: context(model),
			revision: 1,
			value: project
		)))
		_ = ContextNavigationReducer.reduce(
			&model,
			edit
		)
		_ = PreferenceReducer.reduce(
			&model,
			edit
		)
		#expect(model.preferences.selectedModelID == "global")
		_ = ContextNavigationReducer.reduce(
			&model,
			received
		)
		_ = PreferenceReducer.reduce(
			&model,
			received
		)
		#expect(model.preferences.selectedModelID == "global")
	}

	private func fixture(path: String? = "/project") -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: path
		))
		model.connection.isConnected = true
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
	}

	private func option(
		_ id: String,
		efforts: [String],
		isDefault: Bool
	) -> ModelOption
	{
		ModelOption(json: ["model": id,
							"isDefault": isDefault,
							"supportedReasoningEfforts": efforts.map
							{
							["reasoningEffort": $0]
							}])!
	}

	private func store(
		_ storage: LocalStorage,
		models: [ModelOption] = []
	) -> WorkspaceStateStore
	{
		var model = fixture()
		model.preferences.models = models
		return WorkspaceStateStore(
			model: model,
			service: AppServer(),
			storage: storage,
			persistence: storage.workspacePersistenceScheduler,
			reducers: [PreferenceReducer.reducer]
		)
	}
}
