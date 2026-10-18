import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ComposerFileCompletionTests
{
	@Test(
		.timeLimit(.minutes(1))
	) func retiredResultsAndReentrantOwnerChangesCannotAttachToAnotherDraft() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			let directory = FileManager.default.temporaryDirectory
				.appendingPathComponent(
					"completion-\(UUID())",
					isDirectory: true
				)
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			do
			{
				try Data().write(to: directory.appendingPathComponent("first.txt"))
				try Data().write(to: directory.appendingPathComponent("second.txt"))
				return directory
			}
			catch
			{
				try? FileManager.default.removeItem(at: directory)
				throw error
			}
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(
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
			window.isReleasedWhenClosed = false
			window.contentViewController = controller
			defer
			{
				controller.fileSearchPopover?.close()
				controller.fileIndexRuntime.shutdown()
				window.contentViewController = nil
				window.close()
			}
			controller.render(snapshot(
				root: directory.path,
				draft: "@fi"
			))
			await controller.fileIndexRuntime.job?.value
			try #require(controller.fileIndexRuntime.index != nil)
			window.orderFront(nil)
			window.layoutIfNeeded()
			controller.composer.setSelectedRange(NSRange(
				location: 3,
				length: 0
			))
			controller.showAtFileCompletionIfNeeded()
			let stack = try #require(controller.fileResultsStack)
			let retired = try #require(stack.arrangedSubviews.first as? NSButton)
			controller.updateFileResults(query: "second")
			let current = try #require(stack.arrangedSubviews.first as? NSButton)
			try #require(controller.fileSearchPopover?.isShown == true && current !== retired)
			var attached: [String] = []
			controller.onAddContext =
			{
				attached.append($0.path ?? "")
			}
			try #require(retired.dispatchConfiguredAction())
			#expect(attached.isEmpty && controller.composer.string == "@fi")
			#expect(controller.fileSearchPopover?.isShown == true)
			try #require(current.dispatchConfiguredAction())
			#expect(attached == ["second.txt"])
			#expect(controller.composer.string.isEmpty)

			controller.composer.string = "@fi"
			controller.composer.setSelectedRange(NSRange(
				location: 3,
				length: 0
			))
			controller.showAtFileCompletionIfNeeded()
			let reentrant = try #require(stack.arrangedSubviews.first as? NSButton)
			var replacementAttachments = 0
			controller.onDraftChange =
			{
				[weak controller] _ in
				guard let controller
				else
				{
					return
				}
				var next = snapshot(
					root: directory.path,
					draft: "Replacement draft"
				)
				next.composerDraftLifetime = 1
				controller.render(next)
				controller.onAddContext =
				{
					_ in replacementAttachments += 1
				}
			}
			try #require(reentrant.dispatchConfiguredAction())
			#expect(attached == ["second.txt"] && replacementAttachments == 0)
			#expect(controller.composer.string == "Replacement draft")
		}
	}

	private func snapshot(
		root: String,
		draft: String
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: root,
			threads: [],
			selectedThreadID: nil,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: draft,
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
