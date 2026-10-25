import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{

	@Test func projectModelPreferenceRestoresAfterProjectSwitch() async throws
	{
		let first = try await makeProject()
		let second = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: first)
			try? FileManager.default.removeItem(at: second)
		}
		let storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"CodexGUIContextTests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: storageDirectory)
		}
		let projectContextStore = ProjectContextStore(directory: storageDirectory)
		let service = MockCodexService()
		service.availableModels = [
			ModelOption(json: [
				"model": "first-model",
				"displayName": "First",
				"isDefault": true,
				"supportedReasoningEfforts": [
					["reasoningEffort": "low"],
					["reasoningEffort": "high"],
				],
			])!
		]
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults),
			projectContextStore: projectContextStore
		)
		await state.inputs.connect()
		service.configureCheckout(first)
		state.inputs.openProject(first)
		var firstContext = ProjectContext()
		firstContext.modelPreference = ProjectModelPreference(
			modelID: "first-model",
			effort: "high"
		)
		state.inputs.updateProjectContext(firstContext)
		#expect(state.currentSnapshot.selectedEffort == "high")
		service.configureCheckout(second)
		state.inputs.openProject(second)
		#expect(state.currentSnapshot.selectedEffort == nil)
		var secondContext = ProjectContext()
		secondContext.modelPreference = ProjectModelPreference(
			modelID: "first-model",
			effort: "low"
		)
		state.inputs.updateProjectContext(secondContext)
		#expect(state.currentSnapshot.selectedEffort == "low")
		service.configureCheckout(first)
		state.inputs.openProject(first)
		#expect(await awaitApplicationStateCondition(state)
		{
			state.currentSnapshot.projectContext.modelPreference?.effort == "high"
		})
		#expect(state.currentSnapshot.selectedEffort == "high")
		#expect(state.currentSnapshot.projectContext.modelPreference?.effort == "high")
	}
}
