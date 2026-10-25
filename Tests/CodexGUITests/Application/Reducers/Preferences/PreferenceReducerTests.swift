import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite(
	"Preference scope and precedence"
)
struct PreferenceReducerTests
{

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
