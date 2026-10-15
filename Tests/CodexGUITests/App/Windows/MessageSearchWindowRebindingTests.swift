import AppKit
import Testing

@testable import CodexGUI

// Keep the search sheet owner stable across asynchronous store rebinding.
@Suite @MainActor
struct MessageSearchWindowRebindingTests
{

	@Test(.testTiming)
	func searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding(
	) async throws
	{
		let body = TestTiming.begin("test.body")
		defer
		{
			body.end()
		}
		let storeFixture = TestTiming.begin("fixture.store.construct")
		let firstFixture = try await CapturedIntentStoreFixture.makeStore(threadID: "first-thread")
		defer
		{
			firstFixture.cleanup()
		}
		let first = firstFixture.store
		let service = firstFixture.service
		let nextFixture = try await CapturedIntentStoreFixture.makeStore(
			threadID: "next-thread",
			sharing: firstFixture
		)
		defer
		{
			nextFixture.cleanup()
		}
		let next = nextFixture.store
		storeFixture.end()
		let firstConnection = TestTiming.begin("store.connect.first")
		await first.inputs.connect()
		firstConnection.end()
		let nextConnection = TestTiming.begin("store.connect.next")
		await next.inputs.connect()
		nextConnection.end()
		// Preparing and connecting both stores is independent of native sheet ownership.
		// The selection await below remains protected because the live sheet must stay owned.
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			_ = NSApplication.shared
			let nativeFixture = TestTiming.begin("fixture.window.construct")
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
			nativeFixture.end()
			defer
			{
				let cleanup = TestTiming.begin("native.window.cleanup")
				window.close()
				cleanup.end()
			}
			let showSheet = TestTiming.begin("native.sheet.show")
			controller.showMessageSearch()
			showSheet.end()
			let sheet = try #require(window.attachedSheet)
			controller.messageSearch.onSearch?("first query")
			let selection = TestTiming.begin("store.selectThread.await")
			try #require(first.currentSnapshot.selectedThreadID != service.thread.id)
			let selectionHandle = try #require(first.inputs.selectThread(service.thread.id))
			#expect(await selectionHandle.wait() == .finished)
			selection.end()
			#expect(first.currentSnapshot.selectedThreadID == service.thread.id)
			#expect(window.attachedSheet === sheet)
			#expect(first.model.contextNavigation.messageSearch?.query == "first query")
			first.inputs.newChat()
			#expect(first.model.conversations.selectedConversation == .newChat)
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

}
