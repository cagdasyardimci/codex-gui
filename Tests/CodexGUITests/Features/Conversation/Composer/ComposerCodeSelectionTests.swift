import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.timeLimit(.minutes(1))
) @MainActor
struct ComposerCodeSelectionTests
{
	@Test
	func capturedAttachmentReceiverKeepsItsCallbackAndExpiresWithTheDraft()
	{
		let controller = ConversationViewController()
		var first: [ComposerContextItem] = []
		var later: [ComposerContextItem] = []
		controller.onAddContext =
		{
			first.append($0)
		}
		let receive = controller.makeContextAttachmentReceiver()
		controller.onAddContext =
		{
			later.append($0)
		}
		let item = ComposerContextItem(
			kind: .fileReference,
			title: "file.swift",
			path: "file.swift"
		)
		receive(item)
		#expect(first == [item])
		#expect(later.isEmpty)
		controller.selectionGeneration += 1
		receive(item)
		#expect(first == [item])
		#expect(later.isEmpty)
	}

	@Test(
		arguments: [false, true],
		["thread", "draft", "window"]
	)
	func selectionChangesWhileReadingSuppressCodeAndErrorSheets(
		fails: Bool,
		change: String
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(
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
			window.isReleasedWhenClosed = false
			window.contentViewController = controller
			defer
			{
				window.close()
			}
			controller.render(snapshot())
			window.makeKeyAndOrderFront(nil)
			let reader = SuspendedCodeReader()
			let generation = controller.selectionGeneration
			let task = Task
			{
				await controller.loadCodeSelection(
					file: URL(fileURLWithPath: "/project/file.swift"),
					project: URL(fileURLWithPath: "/project"),
					generation: generation,
					window: window,
					receiveAttachment: controller.makeContextAttachmentReceiver(),
					readFile:
					{
						_, _ in try await reader.read(fails: fails)
					}
				)
			}
			await reader.waitForRead()
			if change == "window"
			{
				window.close()
				#expect(!window.isVisible)
			}
			else
			{
				controller.render(snapshot(
					threadID: change == "draft" ? "first" : "second",
					lifetime: change == "draft" ? 1 : 0
				))
				#expect(controller.selectionGeneration != generation)
			}
			await reader.finish()
			await task.value
			#expect(window.attachedSheet == nil)
		}
	}

	private func snapshot(
		threadID: String = "first",
		lifetime: Int = 0
	) -> ConversationSnapshot
	{
		var value = ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: threadID,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "Draft",
			canSend: true,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		value.composerDraftLifetime = lifetime
		return value
	}
}

private actor SuspendedCodeReader
{
	private var started = false
	private var startWaiter: CheckedContinuation<Void, Never>?
	private var finishWaiter: CheckedContinuation<Void, Never>?

	func read(fails: Bool) async throws -> ComposerCodeFile
	{
		started = true
		await withCheckedContinuation
		{
			finishWaiter = $0
			startWaiter?.resume()
			startWaiter = nil
		}
		if fails
		{
			throw FileViewerFailure.tooLarge
		}
		return ComposerCodeFile(
			relativePath: "file.swift",
			contents: "let value = 1"
		)
	}

	func waitForRead() async
	{
		if !started
		{
			await withCheckedContinuation
			{
				startWaiter = $0
			}
		}
	}

	func finish()
	{
		finishWaiter?.resume()
		finishWaiter = nil
	}
}
