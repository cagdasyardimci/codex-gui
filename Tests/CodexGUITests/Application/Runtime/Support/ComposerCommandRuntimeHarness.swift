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
			storage: LocalStorage(defaults: defaults)
		)
	}

	func start() async throws
	{
		await state.inputs.connect()
		service.base.configureCheckout(project)
		state.inputs.openProject(project)
		try #require(await eventually
		{
			self.state.currentSnapshot.canSend
		})
		_ = await state.inputs.selectThread(service.base.thread.id)?.wait()
		try #require(await eventually
		{
			self.state.currentSnapshot.canSend
		})
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

	func eventually(_ condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 200
		{
			if condition()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return condition()
	}
}
