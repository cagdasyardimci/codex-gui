import Foundation
import Testing
@testable import CodexGUI

/// Runs the production store factory and input boundary without a real model call.
@MainActor
final class ComposerCommandRuntimeHarness
{
	let service = ComposerCommandRuntimeService()
	let project: URL
	let state: WorkspaceTestFixture
	private let defaults: UserDefaults
	private let suite: String
	var store: WorkspaceStateStore
	{
		state.store
	}
	var conversation: ConversationKey
	{
		.thread(service.base.thread.id)
	}
	var draft: ComposerDraft
	{
		store.model.composer.drafts[conversation] ?? ComposerDraft()
	}

	init() throws
	{
		project = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ComposerCommandRuntime-\(UUID())",
			isDirectory: true
		).standardizedFileURL.resolvingSymlinksInPath()
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		suite = "ComposerCommandRuntime.\(UUID())"
		defaults = try #require(UserDefaults(suiteName: suite))
		service.base.availableModels = [ModelOption(json: [
			"id": "fixture-model",
			"model": "fixture-model",
			"isDefault": true,
			"defaultReasoningEffort": "medium",
			"supportedReasoningEfforts": [["reasoningEffort": "medium"]],
		])!]
		state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaults),
			// drainPersistence must drain this fixture's real context worker, not
			// unrelated tests sharing the application's default storage directory.
			projectContextStore: ProjectContextStore(directory: project
				.appendingPathComponent("app-support/project-context"))
		)
	}

	func start() async throws
	{
		let timing = TestTiming.begin("composer.start-phases")
		defer
		{
			timing.end()
		}
		timing.mark("connect.begin")
		await state.inputs.connect()
		timing.mark("connect.end")
		service.base.configureCheckout(project)
		timing.mark("open-project.begin")
		state.inputs.openProject(project)
		// Context IO is independent of connection acknowledgement and actor scheduling.
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSend
		}
		try #require(state.currentSnapshot.canSend)
		timing.mark("open-project.ready")
		timing.mark("select-thread.begin")
		_ = await state.inputs.selectThread(service.base.thread.id)?.wait()
		timing.mark("select-thread.acknowledged")
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSend
		}
		try #require(state.currentSnapshot.canSend)
		timing.mark("select-thread.ready")
	}

	func close()
	{
		state.shutdown()
		service.cancelPendingCalls()
		defaults.removePersistentDomain(forName: suite)
		try? FileManager.default.removeItem(at: project)
	}

	func attachFile() throws -> ComposerContextItem
	{
		let file = project.appendingPathComponent("evidence.txt")
		try Data("Fixture content".utf8).write(to: file)
		let item = ComposerContextItem(
			kind: .fileReference,
			title: "Evidence",
			path: "evidence.txt"
		)
		state.inputs.addDraftContext(item)
		return item
	}

	func detail(
		id: String,
		turns: [CodexTurn] = []
	) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: [
				"id": id,
				"name": id,
				"cwd": project.path,
				"status": ["type": "idle"],
			])!,
			turns: turns,
			nextTurnsCursor: nil
		)
	}

	func turn(
		id: String,
		status: String,
		items: [[String: Any]] = []
	) -> CodexTurn
	{
		CodexTurn(json: ["id": id, "status": status, "items": items])!
	}

	func awaitSnapshot(matching condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		await awaitWorkspaceSnapshot(store)
		{
			_ in condition()
		}
		return condition()
	}
}
