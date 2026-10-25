import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationTitleTests
{

	@Test func notificationsRefreshAndPersistPinnedMetadataBeforeAListRefresh() throws
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		model.preferences.pinnedTasks = [summary()]
		for name in ["Generated title", "External rename"]
		{
			let result = observeTitle(
				name,
				model: &model
			)
			let live = try #require(model.conversations.threads.first)
			let pin = try #require(model.preferences.pinnedTasks.first)
			#expect(live.displayTitle == name)
			#expect(pin.displayTitle == live.displayTitle)
			#expect(model.conversations.pendingList == nil)
			let write = try #require(result.effects.compactMap
			{
				if case .persistPreference(let write) = $0
				{
					return write
				}
				return nil
			}.first)
			#expect(write.context.workspace == model.identity)
			#expect(write.context.generation == model.connection.generation)
			#expect(model.preferences.pendingPreferenceWrites[.taskPin("thread")] == write.context)
			guard case .taskPin(
				let persisted,
				pinned: true
			) = write.value
			else
			{
				Issue.record("Expected the renamed task pin to be persisted")
				return
			}
			#expect(persisted.name == name)
		}
	}

	@discardableResult
	private func observeTitle(
		_ name: String?,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ConversationReducer.reduce(
			&model,
			.execution(.backendObserved(
				context(model),
				.threadNameUpdated(
					threadId: "thread",
					name: name
				)
			))
		)
	}

	private func workspace() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/titles"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID()
		)
	}

	private func summary() -> ThreadSummary
	{
		ThreadSummary(json: ["id": "thread", "cwd": "/tmp/titles", "preview": "Original prompt"])!
	}
}
