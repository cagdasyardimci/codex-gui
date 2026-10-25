import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RestoredRemoteConversationRuntimeTests
{
	@Test(arguments: [false, true])
	func phoneTurnAllowsMacFollowupDespiteLateRecovery(_ recoveryArrivesAfterCompletion: Bool)
		async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		let service = fixture.service.base
		let threadID = service.thread.id
		service.suspendNextRead = true
		service.emit(.threadStatusChanged(
			threadId: threadID,
			status: try #require(ThreadStatus(json: ["type": "active", "activeFlags": []]))
		))
		try #require(await service.awaitReadiness
		{
			service.pendingRead != nil
		})
		let recovery = try #require(fixture.store.model.conversations.pendingReads.values.first
		{
			$0.context.threadID == threadID && $0.purpose == .recovery
		})
		let handle = try #require(fixture.store.operation(for: recovery.context))
		let running = try #require(CodexTurn(json: [
			"id": "phone-turn",
			"status": "inProgress",
			"items": [],
		]))
		let delayedHistory = ThreadDetail(
			summary: try #require(ThreadSummary(json: [
				"id": threadID,
				"cwd": fixture.project.path,
				"status": ["type": "active"],
			])),
			turns: [running],
			nextTurnsCursor: nil
		)
		service.emit(.turnStarted(
			threadId: threadID,
			turn: running
		))
		service.emit(.agentMessageDelta(
			threadId: threadID,
			turnId: running.id,
			itemId: "phone-answer",
			text: "Phone reply"
		))
		if !recoveryArrivesAfterCompletion
		{
			service.finishPendingRead(with: delayedHistory)
			#expect(await handle.wait() == .finished)
		}
		let completed = try #require(CodexTurn(json: [
			"id": running.id,
			"status": "completed",
			"items": [
				["id": "phone-answer", "type": "agentMessage", "text": "Phone reply"],
			],
		]))
		service.savedTurns = [completed]
		service.emit(.turnCompleted(
			threadId: threadID,
			turn: completed
		))
		try #require(await fixture.awaitSnapshot
		{
			fixture.store.model.conversations.content[.thread(threadID)]?.loadedTurns.last?.status
				== "completed"
		})
		if recoveryArrivesAfterCompletion
		{
			service.finishPendingRead(with: delayedHistory)
			#expect(await handle.wait() == .finished)
		}
		#expect(!fixture.store.model.execution.needsReconciliation)
		#expect(!fixture.store.model.execution.hasUncertainRequest)
		#expect(fixture.state.currentSnapshot.canSend)
		#expect(service.turnStartCount == 0)
		fixture.state.inputs.updateDraft("Mac followup")
		let send = try #require(fixture.state.inputs.send())
		#expect(await send.wait() == .finished)
		#expect(service.turnStartCount == 1)
	}

	@Test
	func restoredChatSubscribesAndReceivesMobileSettingsAndMessages() async throws
	{
		let defaults = try IsolatedUserDefaultsFixture(prefix: "RestoredRemoteConversation")
		let project = FileManager.default.temporaryDirectory
			.appendingPathComponent("RestoredRemoteConversation-\(UUID())")
			.standardizedFileURL.resolvingSymlinksInPath()
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		defer
		{
			defaults.cleanup()
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.configureCheckout(project)
		service.availableModels = [ModelOption(json: [
			"model": "desktop-model",
			"isDefault": true,
			"defaultReasoningEffort": "medium",
			"supportedReasoningEfforts": [["reasoningEffort": "medium"]],
		])!, ModelOption(json: [
			"model": "phone-model",
			"defaultReasoningEffort": "medium",
			"supportedReasoningEfforts": [["reasoningEffort": "low"]],
		])!]
		service.resumedSettings = ThreadSettings(json: [
			"cwd": project.path,
			"model": "phone-model",
			"effort": "low",
		])
		let storage = LocalStorage(defaults: defaults.defaults)
		storage.rememberProject(project)
		storage.saveSelectedThreadID(
			service.thread.id,
			for: project
		)
		storage.saveRemoteAccessEnabled(true)
		let store = WorkspaceStoreFactory.makeSource(dependencies: WorkspaceStoreDependencies(
			service: service,
			storage: storage,
			projectContextStore: ProjectContextStore(
				directory: project.appendingPathComponent("app-support/project-context")
			)
		))
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		await awaitWorkspaceSnapshot(store)
		{
			$0.selectedThreadID == service.thread.id
				&& store.model.conversations.content[.thread(service.thread.id)]?
				.hasLoadedHistory == true
				&& store.model.remoteAccess.pending == nil
		}
		#expect(service.resumedThreadIDs == [service.thread.id])
		#expect(service.remoteControlEnableRequests == [true])
		#expect(store.model.remoteAccess.status?.status == .connected)
		#expect(store.currentSnapshot.selectedModelID == "phone-model")
		#expect(store.currentSnapshot.selectedEffort == "low")
		let settings = try #require(ThreadSettings(json: [
			"cwd": project.path,
			"model": "desktop-model",
			"effort": "medium",
			"serviceTier": "default",
		]))
		service.emit(.threadSettingsUpdated(
			threadId: service.thread.id,
			settings: settings
		))
		#expect(store.currentSnapshot.selectedModelID == "desktop-model")
		#expect(store.currentSnapshot.selectedEffort == "medium")
		let turn = try #require(CodexTurn(json: [
			"id": "mobile-turn",
			"status": "inProgress",
			"items": [],
		]))
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: turn
		))
		service.emit(.agentMessageDelta(
			threadId: service.thread.id,
			turnId: turn.id,
			itemId: "mobile-reply",
			text: "Mobile reply"
		))
		#expect(store.currentSnapshot.entries.contains
		{
			$0.body == "Mobile reply"
		})
	}
}
