import AppKit
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1))) @MainActor
struct ChatToolsWindowIntegrationTests
{
	@Test func newDraftGetsFreshTabsThatFollowItsFirstMessage() async throws
	{
		_ = NSApplication.shared
		let fixture = try await CapturedIntentStoreFixture.makeStore(threadID: "created")
		defer
		{
			fixture.cleanup()
		}
		let store = fixture.store
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
		defer
		{
			controller.window?.close()
		}
		controller.paneController.openToolsPane()
		let previousTab = try #require(controller.inspector.toolsTabs.selectedTabID)

		store.inputs.newChat()
		#expect(!controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.tabCount == 0)
		controller.paneController.openToolsPane()
		let draftTab = try #require(controller.inspector.toolsTabs.selectedTabID)
		#expect(draftTab != previousTab)
		store.inputs.updateDraft("Start this chat")
		await awaitWorkspaceSnapshot(store)
		{
			$0.canSend
		}
		let submission = try #require(store.inputs.send())
		_ = await submission.wait()

		#expect(store.currentSnapshot.selectedThreadID == "created")
		#expect(controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.selectedTabID == draftTab)
	}
}
