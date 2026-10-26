import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct DesktopConfirmationPanelTests
{
	enum Action: CaseIterable, Sendable
	{
		case returnKey, keypadEnter, escape, confirm
	}

	@Test func dialogKeyboardLoopReachesCloseAndSkipsDisabledActions() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let controller = TaskDeletionConfirmationView()
			let window = TaskDeletionConfirmationPanel(contentViewController: controller)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			controller.dialog.resize(window: window)
			window.layoutIfNeeded()
			window.initialFirstResponder = controller.cancelButton
			#expect(window.makeFirstResponder(nil))
			let parent = InitialResponderReplacingSheetParent()
			parent.prepareForTesting()
			defer
			{
				parent.endSheet(window)
				parent.close()
			}
			window.beginSheet(in: parent)
			{
				_ in
			}
			#expect(window.firstResponder === controller.cancelButton)
			#expect(window.initialFirstResponder === controller.cancelButton)
			window.selectPreviousKeyView(nil)
			#expect(window.firstResponder === controller.closeButton)
			window.selectNextKeyView(nil)
			#expect(window.firstResponder === controller.cancelButton)
			window.selectNextKeyView(nil)
			#expect(window.firstResponder === controller.confirmButton)
			window.selectNextKeyView(nil)
			#expect(window.firstResponder === controller.closeButton)
			window.selectNextKeyView(nil)
			#expect(window.firstResponder === controller.cancelButton)
			controller.confirmButton.isEnabled = false
			window.selectNextKeyView(nil)
			#expect(window.firstResponder === controller.closeButton)
			window.selectPreviousKeyView(nil)
			#expect(window.firstResponder === controller.cancelButton)
		}
	}


	private func savePreview(
		_ view: NSView,
		name: String
	) throws
	{
		guard let path = ProcessInfo.processInfo.environment["CODEX_GUI_COMPONENT_PREVIEW_DIR"]
		else
		{
			return
		}
		let directory = URL(
			fileURLWithPath: path,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(
			to: directory.appendingPathComponent(name + ".png"),
			options: .atomic
		)
	}

}

/// Reproduces AppKit replacing the requested responder while presenting a sheet.
@MainActor
private final class InitialResponderReplacingSheetParent: NSWindow
{
	override func beginSheet(
		_ sheetWindow: NSWindow,
		completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil
	)
	{
		super.beginSheet(
			sheetWindow,
			completionHandler: handler
		)
		sheetWindow.initialFirstResponder = sheetWindow.contentView
	}
}
