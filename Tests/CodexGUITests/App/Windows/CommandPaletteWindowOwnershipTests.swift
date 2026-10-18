import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct CommandPaletteWindowOwnershipTests
{
	@Test func repeatedPresentationKeepsTheExistingSheetAndCallback() async throws
	{
		let fixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			fixture.cleanup()
		}
		await fixture.store.inputs.connect()
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let controller = MainWindowController(
				store: fixture.store,
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
			controller.showCommandPalette()
			let sheet = try #require(window.attachedSheet)
			var choices: [PaletteCommand.Destination] = []
			controller.commandPalette.onChoose =
			{
				choices.append($0)
			}
			controller.showCommandPalette()
			#expect(window.attachedSheet === sheet)
			controller.commandPalette.onChoose?(.action("captured"))
			#expect(choices == [.action("captured")])
			window.endSheet(sheet)
		}
	}

	@Test(arguments: [false, true])
	func presentationActionsRejectRetiredOwners(retireOwner: Bool) async throws
	{
		let fixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			fixture.cleanup()
		}
		await fixture.store.inputs.connect()
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let controller = MainWindowController(
				store: fixture.store,
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
			controller.showCommandPalette()
			let sheet = try #require(window.attachedSheet)
			let choose = try #require(controller.commandPalette.onChoose)
			window.endSheet(sheet)
			if retireOwner
			{
				fixture.store.shutdown()
			}
			choose(.action("search"))
			#expect((window.attachedSheet != nil) == !retireOwner)
			controller.messageSearch.dismiss()
			choose(.action("changes"))
			#expect(controller.inspector.gitChanges.runtime.state.isOpen == !retireOwner)
			#expect(controller.inspector.isShowingDetails == !retireOwner)
			#expect(!controller.inspector.isShowingTools)
		}
	}
}
