import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite(
	"Preference scope and precedence"
)
struct PreferenceReducerTests
{
	@Test func remoteThreadSettingsReachComposerAndLaterLocalChoicesWin() throws
	{
		var model = fixture()
		model.preferences.models = [ModelOption(json: [
			"model": "test-model",
			"isDefault": true,
			"supportedReasoningEfforts": [
				["reasoningEffort": "low"],
				["reasoningEffort": "medium"],
				["reasoningEffort": "high"],
			],
			"serviceTiers": [["id": "priority", "name": "Fast", "description": "Fast"]],
		])!]
		model.preferences.globalModelPreference = ProjectModelPreference(
			modelID: "test-model",
			effort: "medium"
		)
		model.preferences.resolveSelection()
		model.conversations.selectedConversation = .thread("phone")
		let operation = context(model)
		let remote = ThreadSettings(json: [
			"model": "test-model",
			"cwd": "/project",
			"effort": "low",
			"serviceTier": "priority",
		])!
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				operation,
				.threadSettingsUpdated(
					threadId: "phone",
					settings: remote
				)
			))
		)
		var displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "low")
		#expect(displayed.runPreferences.fastMode)
		#expect(model.preferences.selectedEffort == "medium")
		#expect(!model.preferences.runPreferences.fastMode)

		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.effortSelected(
				operation,
				"high"
			))
		)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.fastModeSelected(
				operation,
				false
			))
		)
		displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "high")
		#expect(!displayed.runPreferences.fastMode)

		model.conversations.selectedConversation = .newChat
		displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "high")
		#expect(!displayed.runPreferences.fastMode)

		model.conversations.selectedConversation = .thread("phone")
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				operation,
				.threadSettingsUpdated(
					threadId: "phone",
					settings: remote
				)
			))
		)
		displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "high")
		#expect(!displayed.runPreferences.fastMode)

		let phoneEffort = ThreadSettings(json: [
			"model": "test-model",
			"cwd": "/project",
			"effort": "medium",
			"serviceTier": "priority",
		])!
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				operation,
				.threadSettingsUpdated(
					threadId: "phone",
					settings: phoneEffort
				)
			))
		)
		displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "medium")
		#expect(!displayed.runPreferences.fastMode)

		let phoneFast = ThreadSettings(json: [
			"model": "test-model",
			"cwd": "/project",
			"effort": "medium",
			"serviceTier": "default",
		])!
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				operation,
				.threadSettingsUpdated(
					threadId: "phone",
					settings: phoneFast
				)
			))
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				operation,
				.threadSettingsUpdated(
					threadId: "phone",
					settings: phoneEffort
				)
			))
		)
		displayed = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		#expect(displayed.selectedEffort == "medium")
		#expect(displayed.runPreferences.fastMode)
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

	@Test func logoutDeduplicatesAndFailurePreservesReportedAccount() throws
	{
		var model = fixture()
		let account = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true,
			planType: "pro"
		)
		model.preferences.accountStatus = account
		let operation = context(model)
		let admitted = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutRequested(operation))
		)
		#expect(admitted.effects.count == 1)
		#expect(admitted.effects.contains
		{
			if case .signOut(let value) = $0
			{
				return value == operation
			}
			return false
		})
		#expect(model.preferences.pendingSignOut == operation)
		let repeated = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutRequested(context(model)))
		)
		#expect(repeated.effects.isEmpty)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutFinished(
				operation,
				.failed(OperationFailure(
					message: "Unavailable",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.preferences.accountStatus == account)
		#expect(model.preferences.pendingSignOut == nil)
		#expect(model.preferences.statusMessage == "Could not log out: Unavailable")
	}

	@Test func acceptedLogoutReplacesPendingAccountReadAndIgnoresItsLateReply() throws
	{
		var model = fixture()
		let account = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true
		)
		model.preferences.accountStatus = account
		let oldRead = context(model)
		model.preferences.pendingAccount = oldRead
		let operation = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutRequested(operation))
		)
		let result = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutFinished(
				operation,
				.succeeded(())
			))
		)
		#expect(result.effects.count == 1)
		#expect(result.domainEvents.count == 1)
		#expect(result.domainEvents.contains
		{
			if case .accountSignedOut = $0
			{
				return true
			}
			return false
		})
		#expect(result.effects.contains
		{
			if case .readAccount(let value) = $0
			{
				return value == operation
			}
			return false
		})
		#expect(model.preferences.pendingSignOut == nil)
		#expect(model.preferences.accountStatus == nil)
		#expect(model.preferences.pendingAccount == operation)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.accountReceived(
				oldRead,
				.succeeded(account)
			))
		)
		#expect(model.preferences.accountStatus == nil)
	}

	@Test func logoutReplyFromPreviousTransportCannotClearNewAccount() throws
	{
		var model = fixture()
		let account = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true
		)
		model.preferences.accountStatus = account
		let operation = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutRequested(operation))
		)
		model.connection.generation += 1
		let result = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutFinished(
				operation,
				.succeeded(())
			))
		)
		#expect(result.effects.isEmpty)
		#expect(model.preferences.accountStatus == account)
	}

	@Test(arguments: [true, false])
	func logoutReplyForAnotherRequestCannotRetirePendingLogout(succeeded: Bool) throws
	{
		var model = fixture()
		let account = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true
		)
		model.preferences.accountStatus = account
		let operation = context(model)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutRequested(operation))
		)
		let unrelated = context(model)
		let observation: OperationResult<Void> = succeeded
			? .succeeded(())
			: .failed(OperationFailure(
				message: "Unrelated failure",
				outcomeIsUncertain: false
			))
		let result = PreferenceReducer.reduce(
			&model,
			.preferences(.signOutFinished(
				unrelated,
				observation
			))
		)
		#expect(model.preferences.accountStatus == account)
		#expect(model.preferences.pendingSignOut == operation)
		#expect(model.preferences.signOutError == nil)
		#expect(model.preferences.statusMessage == nil)
		#expect(result.effects.isEmpty)
		#expect(result.domainEvents.isEmpty)
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
