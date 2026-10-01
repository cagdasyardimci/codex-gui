import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func submissionCapturesPreferencesBeforeSuspendedThreadPreparation() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.availableModels = [ModelOption(json: [
			"model": "captured-model",
			"isDefault": true,
			"supportedReasoningEfforts": [["reasoningEffort": "medium"]],
			"serviceTiers": [["id": "express", "name": "Fast", "description": "Fixture fast tier"]],
		])!]
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		state.inputs.selectModel("captured-model")
		state.inputs.selectEffort("medium")
		state.inputs.selectApprovalMode(.approveForMe)
		state.inputs.setFastMode(true)
		#expect(state.currentSnapshot.fastMode)
		state.inputs.updateDraft("Captured request")
		service.suspendThreadStart = true
		let submission = try #require(state.inputs.send())
		try #require(await waitUntil
		{
			service.pendingThreadStart != nil
		})
		state.inputs.selectModel(nil)
		state.inputs.selectEffort(nil)
		state.inputs.selectApprovalMode(.fullAccess)
		state.inputs.setFastMode(false)
		service.pendingThreadStart?.resume(returning: ThreadDetail(
			summary: service.thread,
			turns: [],
			nextTurnsCursor: nil
		))
		service.pendingThreadStart = nil
		_ = await submission.wait()
		let captured = try #require(service.capturedTurnPreferences.first)
		#expect(captured.modelID == "captured-model")
		#expect(captured.effort == "medium")
		#expect(captured.preferences == RunPreferences(
			approvalMode: .approveForMe,
			fastMode: true
		))
		#expect(service.capturedTurnServiceTiers.first == "express")
		#expect(state.currentSnapshot.approvalMode == .fullAccess)
		#expect(!state.currentSnapshot.fastMode)
	}

	@Test func unavailableSavedModelAndEffortBlockSendUntilExplicitChoice() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let storage = makeStorage()
		storage.saveModelPreference(
			modelID: "old-model",
			effort: "high"
		)
		let service = MockCodexService()
		service.availableModels = [
			ModelOption(json: [
				"model": "current",
				"displayName": "Current",
				"isDefault": true,
				"supportedReasoningEfforts": [["reasoningEffort": "medium"]],
			])!
		]
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try #require(await waitUntil
		{
			state.currentSnapshot.preferenceWarning != "Project context is loading."
		})

		#expect(state.currentSnapshot.selectedModelID == "old-model")
		#expect(state.currentSnapshot.selectedEffort == "high")
		#expect(state.currentSnapshot.preferenceWarning?.contains("old-model") == true)
		#expect(!state.currentSnapshot.canSend)
		state.inputs.selectModel("current")
		#expect(state.currentSnapshot.preferenceWarning == nil)
		#expect(state.currentSnapshot.selectedEffort == nil)
		state.inputs.selectEffort("high")
		#expect(state.currentSnapshot.preferenceWarning?.contains("high") == true)
		#expect(!state.currentSnapshot.canSend)
		state.inputs.selectEffort("medium")
		#expect(state.currentSnapshot.preferenceWarning == nil)
		#expect(
			storage.modelPreference
				== LocalStorage.ModelPreference(
					modelID: "current",
					effort: "medium"
				)
		)
	}

	@Test func failedModelListRemainsVisibleAndBlocksSendUntilReconnect() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.modelsError = AppServerError.protocolError("temporary model failure")
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)

		#expect(state.currentSnapshot.preferenceWarning?
			.contains("temporary model failure") == true)
		#expect(!state.currentSnapshot.canSend)
		state.inputs.selectModel(nil)
		#expect(!state.currentSnapshot.canSend)

		service.modelsError = nil
		await state.inputs.connect()
		#expect(state.currentSnapshot.preferenceWarning == nil)
		#expect(state.currentSnapshot.canSend)
	}

	@Test func projectModelPreferenceRestoresAfterProjectSwitch() async throws
	{
		let first = try makeProject()
		let second = try makeProject()
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
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage(),
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
		#expect(await waitUntil
		{
			state.currentSnapshot.projectContext.modelPreference?.effort == "high"
		})
		#expect(state.currentSnapshot.selectedEffort == "high")
		#expect(state.currentSnapshot.projectContext.modelPreference?.effort == "high")
	}
}
