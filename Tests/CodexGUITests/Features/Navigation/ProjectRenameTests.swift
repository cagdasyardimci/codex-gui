import AppKit
import Testing
@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ProjectRenameTests
{
	@Test func referenceLayoutAndSelectedName() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let parent = window(controller)
		defer
		{
			parent.close()
		}
		let project = URL(fileURLWithPath: "/tmp/rename-project")
		controller.editProject(project)
		let panel = try #require(parent.attachedSheet as? ProjectRenamePanel)
		let dialog = try #require(panel.contentViewController as? ProjectRenameViewController)
		#expect(dialog.view.frame.size == NSSize(
			width: 420,
			height: 186
		))
		#expect(dialog.headingLabel.stringValue == "Rename project")
		#expect(dialog.subtitleLabel.stringValue == "Keep it short and recognizable")
		#expect(dialog.input.field.stringValue == "rename-project")
		let editor = try #require(dialog.input.field.currentEditor() as? NSTextView)
		#expect(editor.selectedRange() == NSRange(
			location: 0,
			length: 14
		))
		#expect(dialog.saveButton.frame.maxX == dialog.input.frame.maxX)
		#expect(dialog.cancelButton.frame.maxX + 12 == dialog.saveButton.frame.minX)
		#expect(dialog.input.field.accessibilityLabel() == "Project name")
		for appearance in [NSAppearance.Name.darkAqua, .aqua]
		{
			panel.appearance = NSAppearance(named: appearance)
			dialog.view.layoutSubtreeIfNeeded()
			if let directory = ProcessInfo.processInfo
				.environment["CODEX_PROJECT_RENAME_EVIDENCE_DIR"]
			{
				let bitmap = try #require(dialog.view
					.bitmapImageRepForCachingDisplay(in: dialog.view.bounds))
				dialog.view.cacheDisplay(
					in: dialog.view.bounds,
					to: bitmap
				)
				let data = try #require(bitmap.representation(
					using: .png,
					properties: [:]
				))
				try data
					.write(to: URL(fileURLWithPath: directory)
						.appendingPathComponent(appearance.rawValue + ".png"))
			}
		}
		panel.finish(false)
	}

	@Test func returnAndKeypadEnterSaveCapturedProjectAndCallbackOnce() async throws
	{
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
			controller.onRenameProject =
			{
				saved.append(($0, $1))
			}
			controller.editProject(project)
			let panel = try #require(parent.attachedSheet as? ProjectRenamePanel)
			let dialog = try #require(panel.contentViewController as? ProjectRenameViewController)
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
			panel.sendEvent(event)
			dialog.saveButton.performClick(nil)
			for _ in 0 ..< 20 where parent.attachedSheet != nil
			{
				try await Task.sleep(for: .milliseconds(10))
			}
			#expect(saved.count == 1)
			#expect(saved.first?.0 == project)
			#expect(saved.first?.1 == "New name")
		}
	}

	@Test func cancelCloseEscapeAndChangedScopeNeverSave() async throws
	{
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
			let dialog = try #require(panel.contentViewController as? ProjectRenameViewController)
			switch action
			{
			case 0: dialog.cancelButton.performClick(nil)
			case 1: dialog.closeButton.performClick(nil)
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
				dialog.saveButton.performClick(nil)
			}
			for _ in 0 ..< 20 where parent.attachedSheet != nil
			{
				try await Task.sleep(for: .milliseconds(10))
			}
			#expect(parent.attachedSheet == nil)
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
		parent.isReleasedWhenClosed = false
		parent.contentViewController = controller
		parent.orderFront(nil)
		return parent
	}
}
