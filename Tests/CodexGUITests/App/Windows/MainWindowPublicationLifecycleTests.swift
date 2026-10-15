import AppKit
import Testing

@testable import CodexGUI

// The search sheet changes application focus during the window publication lifecycle.
@Suite @MainActor
struct MainWindowPublicationLifecycleTests
{

	@Test(.testTiming)
	func closedWindowDetachesItsStorePublicationObserver() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		timing.mark("fixture.store.ready")
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		timing.mark("store.connect.begin")
		await store.inputs.connect()
		timing.mark("store.connect.end")
		// Store preparation and connection do not use application-wide UI state.
		// Keep the sheet, publication assertions and window dismissal under one permit.
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			timing.mark("native.begin")
			_ = NSApplication.shared
			let controller = MainWindowController(
				store: store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				}
			)
			defer
			{
				controller.window?.close()
			}
			controller.showMessageSearch()
			timing.mark("native.sheet.shown")
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
			timing.mark("native.window.closed")
			#expect(store.model.contextNavigation.messageSearch == nil)
			#expect(store.model.contextNavigation.messageSearchContext == nil)
			#expect(store.model.contextNavigation.pendingMessageSearch == nil)
			store.inputs.updateDraft("Closed")
			#expect(drafts == ["Visible"])
		}

	}

}
