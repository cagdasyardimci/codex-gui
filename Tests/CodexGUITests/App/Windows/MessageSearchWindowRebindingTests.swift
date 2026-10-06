import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct MessageSearchWindowRebindingTests
{

	@Test func searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding(
	) async throws
	{
		_ = NSApplication.shared
		let (first, service) = CapturedIntentStoreFixture.makeStore(threadID: "first-thread")
		let (next, _) = CapturedIntentStoreFixture.makeStore(threadID: "next-thread")
		defer
		{
			first.shutdown()
			next.shutdown()
		}
		await first.inputs.connect()
		await next.inputs.connect()
		let controller = MainWindowController(
			store: first,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		defer
		{
			window.close()
		}
		controller.showMessageSearch()
		let sheet = try #require(window.attachedSheet)
		controller.messageSearch.onSearch?("first query")
		_ = await first.inputs.selectThread(service.thread.id)?.wait()
		#expect(window.attachedSheet === sheet)
		#expect(first.model.contextNavigation.messageSearch?.query == "first query")
		first.inputs.newChat()
		#expect(window.attachedSheet === sheet)
		#expect(first.model.contextNavigation.messageSearchContext != nil)
		next.inputs.searchMessages("next query")
		controller.configureMessageSearchActions(target: WorkspaceIntentTarget(
			store: next,
			snapshot: next.currentSnapshot
		))
		#expect(window.attachedSheet == nil)
		#expect(first.model.contextNavigation.messageSearch == nil)
		#expect(first.model.contextNavigation.messageSearchContext == nil)
		#expect(first.model.contextNavigation.pendingMessageSearch == nil)
		#expect(next.model.contextNavigation.messageSearch?.query == "next query")
		#expect(next.model.contextNavigation.messageSearchContext != nil)
	}

}
