import AppKit
import Testing
@testable import CodexGUI

// Native sheet focus and keyboard routing are application-wide while dismissal awaits.
@Suite(
	.serialized,
	.testTiming
) @MainActor
struct ProjectRenameTests
{

	@Test(.timeLimit(.minutes(1)))
	func returnAndKeypadEnterSaveCapturedProjectAndCallbackOnce() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			for (characters, keyCode) in [("\r", UInt16(36)), ("\u{3}", UInt16(76))]
			{
				let controller = NavigationViewController()
				let parent = window(controller)
				defer
				{
					parent.close()
				}
				let project = URL(fileURLWithPath: "/tmp/original-project")
				var saved: [(URL, String)] = []
				let (saves, continuation) = AsyncStream<Void>.makeStream()
				defer
				{
					continuation.finish()
				}
				controller.onRenameProject =
				{
					saved.append(($0, $1))
					continuation.yield(())
				}
				controller.editProject(project)
				let panel = try #require(parent.attachedSheet as? ProjectRenamePanel)
				let dialog = try #require(panel
					.contentViewController as? ProjectRenameViewController)
				controller.onRenameProject =
				{
					_, _ in Issue.record("Callback was redirected")
				}
				let editor = try #require(dialog.input.field.currentEditor() as? NSTextView)
				editor.string = "  New name  "
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
					keyCode: keyCode
				))
				let actionTiming = TestTiming.begin(
					"sheet.action",
					detail: "save-key-\(keyCode)"
				)
				panel.sendEvent(event)
				actionTiming.end()
				let dismissalTiming = TestTiming.begin(
					"sheet.dismissal",
					detail: "save-key-\(keyCode)"
				)
				var saveEvents = saves.makeAsyncIterator()
				try #require(await saveEvents.next() != nil)
				dismissalTiming.end()
				#expect(parent.attachedSheet == nil)
				#expect(saved.count == 1)
				#expect(saved.first?.0 == project)
				#expect(saved.first?.1 == "New name")
				try #require(dialog.saveButton.dispatchConfiguredAction())
				#expect(saved.count == 1)
			}
		}
	}

	@Test func cancelCloseEscapeAndChangedScopeNeverSave() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			for action in 0 ..< 4
			{
				let controller = NavigationViewController()
				let parent = window(controller)
				defer
				{
					parent.close()
				}
				controller.onRenameProject =
				{
					_, _ in Issue.record("Unexpected rename")
				}
				controller.editProject(URL(fileURLWithPath: "/tmp/project"))
				let panel = try #require(parent.attachedSheet as? ProjectRenamePanel)
				let dialog = try #require(panel
					.contentViewController as? ProjectRenameViewController)
				let actionTiming = TestTiming.begin(
					"sheet.action",
					detail: "cancel-\(action)"
				)
				switch action
				{
				case 0: try #require(dialog.cancelButton.dispatchConfiguredAction())
				case 1: try #require(dialog.closeButton.dispatchConfiguredAction())
				case 2:
					let escape = try #require(NSEvent.keyEvent(
						with: .keyDown,
						location: .zero,
						modifierFlags: [],
						timestamp: 0,
						windowNumber: panel.windowNumber,
						context: nil,
						characters: "\u{1b}",
						charactersIgnoringModifiers: "\u{1b}",
						isARepeat: false,
						keyCode: 53
					))
					panel.sendEvent(escape)
				default:
					controller.modalScope = NavigationViewController.ModalScope(
						owner: nil,
						selectionEpoch: 1,
						conversation: .newChat,
						draftLifetime: 1,
						projectPath: "/tmp/other"
					)
					try #require(dialog.saveButton.dispatchConfiguredAction())
				}
				actionTiming.end()
				let dismissalTiming = TestTiming.begin(
					"sheet.dismissal",
					detail: "cancel-\(action)"
				)
				for _ in 0 ..< 20 where parent.attachedSheet != nil
				{
					try await Task.sleep(for: .milliseconds(10))
				}
				dismissalTiming.end()
				#expect(parent.attachedSheet == nil)
			}
		}
	}

	private func window(_ controller: NavigationViewController) -> NSWindow
	{
		_ = NSApplication.shared
		let parent = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 500
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		parent.prepareForTesting()
		parent.contentViewController = controller
		parent.orderFront(nil)
		return parent
	}
}
