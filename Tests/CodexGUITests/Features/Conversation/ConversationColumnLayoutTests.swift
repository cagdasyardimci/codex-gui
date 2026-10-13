import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationColumnLayoutTests
{
	@Test(arguments: [false, true])
	func populatedColumnsKeepSymmetricGuttersAfterResizing(resizingPane: Bool) async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		controller.render(snapshot())
		await controller.waitForRendering()
		try #require(controller.displayedRows.count == 2)

		// The screenshot's reading pane is 888 points wide. The larger pane covers
		// an inspector closing; the compact pane and return cover width-dependent reflow.
		for width: CGFloat in [888, 1216, 360, 888]
		{
			if resizingPane
			{
				controller.beginPaneResize()
			}
			window.setContentSize(NSSize(
				width: width,
				height: 876
			))
			controller.view.layoutSubtreeIfNeeded()
			if resizingPane
			{
				controller.endPaneResize()
			}
			controller.view.layoutSubtreeIfNeeded()
			controller.collectionView.layoutSubtreeIfNeeded()

			let pane = controller.view.bounds
			let composer = controller.view.convert(
				controller.composerSurface.bounds,
				from: controller.composerSurface
			)
			#expect(abs(composer.midX - pane.midX) < 0.5)
			#expect(composer.minX >= pane.minX)
			#expect(composer.maxX <= pane.maxX)
			for index in controller.displayedRows.indices
			{
				let attributes = try #require(controller.collectionView.layoutAttributesForItem(
					at: IndexPath(
						item: index,
						section: 0
					)
				))
				let row = controller.view.convert(
					attributes.frame,
					from: controller.collectionView
				)
				let leadingGutter = row.minX - pane.minX
				let trailingGutter = pane.maxX - row.maxX
				#expect(abs(trailingGutter - leadingGutter) < 1)
				#expect(abs(row.midX - composer.midX) < 0.5)
				if width >= 888
				{
					#expect(abs(row.width - 736) < 0.5)
					#expect(abs(row.minX - composer.minX) < 0.5)
					#expect(abs(row.maxX - composer.maxX) < 0.5)
				}
			}
		}
	}

	private func snapshot() -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/column-layout",
			threads: [],
			selectedThreadID: "column-layout",
			entries: [
				ConversationEntry(
					id: "user",
					kind: .user,
					title: "You",
					body: "Keep the conversation and composer centered in the reading pane."
				),
				ConversationEntry(
					id: "reply",
					kind: .agent,
					title: "Codex",
					body: Array(
						repeating: "The populated transcript stays centered "
							+ "while its text reflows.",
						count: 24
					).joined(separator: "\n\n")
				),
			],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Synthetic layout fixture",
			backendDescription: "Synthetic layout fixture",
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
