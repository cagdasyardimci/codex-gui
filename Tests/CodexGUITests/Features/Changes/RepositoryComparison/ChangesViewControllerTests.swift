import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ChangesViewControllerTests
{
	@Test func diffHasVisibleTextAndResizesWithReviewPane() throws
	{
		_ = NSApplication.shared
		let controller = ChangesViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 650
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		window.contentViewController = controller
		let diff = "diff --git a/file.swift b/file.swift\n@@ -3 +3 @@\n-old\n+print(greeting)\n"
		controller.render(
			ConversationSnapshot(
				projectPath: "/tmp/project",
				threads: [],
				selectedThreadID: "thread",
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [ChangeFile(
					path: "file.swift",
					status: "Modified"
				)],
				diff: diff,
				draft: "",
				canSend: false,
				accountDescription: "",
				backendDescription: "",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
		)
		let text = try #require(findText(in: controller.view))
		let scroll = try #require(text.enclosingScrollView)
		for width in [320.0, 220.0, 500.0]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 650
			))
			controller.view.layoutSubtreeIfNeeded()
			let layout = try #require(text.layoutManager)
			let container = try #require(text.textContainer)
			layout.ensureLayout(for: container)
			#expect(text.string.contains("+print(greeting)"))
			#expect(text.frame.width >= scroll.contentSize.width - 1)
			#expect(text.frame.width <= scroll.contentSize.width + 1)
			#expect(text.frame.height >= layout.usedRect(for: container).height)
			#expect(text.frame.height > 30)
			#expect(text.visibleRect.height > 30)
		}
	}

	private func findText(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findText(in: $0)
		}.first
	}
}
