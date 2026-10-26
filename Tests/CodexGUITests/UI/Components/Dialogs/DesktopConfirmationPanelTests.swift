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

	@Test func deletionFlowsUseTheSameCompleteDialogAndActionGeometry() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let task = TaskDeletionConfirmationView()
			let archive = SettingsArchivedChatDeleteView()
			var heights: [CGFloat] = []
			for controller in [task, archive] as [DesktopConfirmationDialogView]
			{
				let shell = try #require(controller.view as? DesktopDialogShell)
				let window = NSWindow(
					contentRect: NSRect(
						x: 0,
						y: 0,
						width: 420,
						height: 200
					),
					styleMask: [.titled],
					backing: .buffered,
					defer: false
				)
				window.prepareForTesting()
				window.contentViewController = controller
				defer
				{
					window.close()
				}
				shell.resize(window: window)
				window.layoutIfNeeded()
				shell.layoutSubtreeIfNeeded()
				heights.append(shell.fittingSize.height)
				#expect(abs(shell.bounds.width - 420) < 1)
				#expect(shell.titleLabel.font?.pointSize == 20)
				#expect(shell.messageLabel?.font?.pointSize == 14)
				#expect(controller.cancelButton.keyEquivalent == "\r")
				#expect(controller.confirmButton.keyEquivalent.isEmpty)
				#expect(controller.confirmButton.hasDestructiveAction)
				#expect(shell.closeButton.keyEquivalent == "\u{1b}")
				let cancel = controller.cancelButton.convert(
					controller.cancelButton.bounds,
					to: shell
				)
				let confirm = controller.confirmButton.convert(
					controller.confirmButton.bounds,
					to: shell
				)
				#expect(abs(cancel.height - 32) < 1)
				#expect(abs(confirm.height - 32) < 1)
				#expect(cancel.width >= 78)
				#expect(confirm.width >= 78)
				#expect(abs(confirm.minX - cancel.maxX - 12) < 1)
				#expect(abs(shell.bounds.maxX - confirm.maxX - 20) < 1)
				#expect(abs(confirm.minY - shell.bounds.minY - 20) < 1)
				let close = shell.closeButton.convert(
					shell.closeButton.bounds,
					to: shell
				)
				let heading = shell.titleLabel.convert(
					shell.titleLabel.bounds,
					to: shell
				)
				#expect(abs(shell.bounds.maxX - close.maxX - 20) < 1)
				#expect(abs(close.midY - heading.midY) < 1)
				#expect(controller.cancelButton.nextKeyView === controller.confirmButton)
				#expect(controller.confirmButton.nextKeyView === controller.closeButton)
				#expect(controller.closeButton.nextKeyView === controller.cancelButton)
				var decisions: [Bool] = []
				controller.onDecision =
				{
					decisions.append($0)
				}
				try #require(controller.closeButton.dispatchConfiguredAction())
				#expect(decisions == [false])
				try #require(controller.confirmButton.dispatchConfiguredAction())
				#expect(decisions == [false, true])
				for appearance: NSAppearance.Name in [.aqua, .darkAqua]
				{
					window.appearance = NSAppearance(named: appearance)
					window.displayIfNeeded()
					try savePreview(
						shell,
						name: (controller === task ? "task-deletion" : "archive-deletion")
							+ (appearance == .aqua ? "-light" : "-dark")
					)
				}
			}
			#expect(heights[0] > heights[1])
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: Action.allCases
	)
	func archivedDeletionHonorsSafeKeysAndOnlyCompletesItsFirstDecision(
		_ action: Action
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let parent = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 800,
					height: 500
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			parent.prepareForTesting()
			let panel = SettingsArchivedChatDeletePanel(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 520,
					height: 146
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			panel.prepareForTesting()
			defer
			{
				panel.close()
				parent.close()
			}
			let responses = AsyncStream<NSApplication.ModalResponse>.makeStream()
			parent.beginSheet(panel)
			{
				response in
				responses.continuation.yield(response)
				responses.continuation.finish()
			}
			switch action
			{
			case .returnKey, .keypadEnter:
				let characters = action == .returnKey ? "\r" : "\u{3}"
				let event = try #require(NSEvent.keyEvent(
					with: .keyDown,
					location: .zero,
					modifierFlags: [],
					timestamp: 0,
					windowNumber: panel.windowNumber,
					context: nil,
					characters: characters,
					charactersIgnoringModifiers: characters,
					isARepeat: false,
					keyCode: action == .returnKey ? 36 : 76
				))
				panel.sendEvent(event)
			case .escape:
				panel.cancelOperation(nil)
			case .confirm:
				panel.finishDecision(true)
			}
			// Repeated or stale actions must not replace the first native sheet response.
			panel.finishDecision(action != .confirm)
			var iterator = responses.stream.makeAsyncIterator()
			#expect(await iterator.next() == (action == .confirm ? .OK : .cancel))
			#expect(await iterator.next() == nil)
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
