import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct MainWindowPublicationLifecycleTests
{

	@Test func closedWindowDetachesItsStorePublicationObserver() async throws
	{
		_ = NSApplication.shared
		let (store, _) = CapturedIntentStoreFixture.makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let controller = MainWindowController(
			store: store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		controller.showMessageSearch()
		controller.messageSearch.onSearch?("needle")
		#expect(store.model.contextNavigation.messageSearchContext != nil)
		var drafts: [String] = []
		controller.onSnapshot =
		{
			drafts.append($0.draft)
		}
		store.inputs.updateDraft("Visible")
		#expect(drafts == ["Visible"])
		controller.window?.close()
		#expect(store.model.contextNavigation.messageSearch == nil)
		#expect(store.model.contextNavigation.messageSearchContext == nil)
		#expect(store.model.contextNavigation.pendingMessageSearch == nil)
		store.inputs.updateDraft("Closed")
		#expect(drafts == ["Visible"])
	}

}
