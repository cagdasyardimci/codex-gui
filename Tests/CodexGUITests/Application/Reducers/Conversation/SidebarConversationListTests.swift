import Foundation
import Testing

@testable import CodexGUI

@MainActor @Suite
struct SidebarConversationListTests
{
	@Test func globalListingIsIndependentAndRejectsSupersededOrForeignResults() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/local"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		let local = try #require(ThreadSummary(json: ["id": "local", "cwd": "/tmp/local"]))
		let foreign = try #require(ThreadSummary(json: ["id": "foreign", "cwd": "/tmp/other"]))
		model.conversations.threads = [local]
		model.conversations.selectedConversation = .thread(local.id)
		func operation(_ archived: Bool = false) -> ConversationListOperation
		{
			ConversationListOperation(
				context: OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID()
				),
				archived: archived,
				allProjects: true
			)
		}
		let first = operation()
		let effects = ConversationReducer
			.reduce(
				&model,
				.conversations(.threadListRequested(first))
			).effects
		#expect(effects.count == 1)
		#expect(model.conversations.pendingList == nil)
		#expect(model.conversations.pendingSidebarList?.context == first.context)
		let wrongRequest = operation()
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				wrongRequest,
				.succeeded([foreign])
			))
		)
		#expect(model.conversations.sidebarThreads == nil)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				first,
				.succeeded([local, foreign])
			))
		)
		#expect(model.conversations.sidebarThreads?.map(\.id) == ["local", "foreign"])
		#expect(model.conversations.threads.map(\.id) == ["local"])
		#expect(model.conversations.selectedConversation == .thread("local"))
		let old = operation()
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(old))
		)
		model.conversations.showingArchived = true
		let archived = operation(true)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(archived))
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				old,
				.succeeded([])
			))
		)
		#expect(model.conversations.pendingSidebarList?.context == archived.context)
		model.connection.generation += 1
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				archived,
				.succeeded([])
			))
		)
		#expect(model.conversations.sidebarThreads?.count == 2)
	}
}
