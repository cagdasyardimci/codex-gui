import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RestoredRemoteConversationRuntimeTests
{
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
