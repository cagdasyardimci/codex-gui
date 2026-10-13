import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Desktop conversation layout",
	.serialized
)
struct DesktopLayoutTests
{
	@Test func populatedChatKeepsSupportedFramesAcrossAppearanceAndResize() async throws
	{
		_ = NSApplication.shared
		let output = ProcessInfo.processInfo.environment["CODEX_GUI_UI_EVIDENCE_DIRECTORY"].map
		{
			URL(fileURLWithPath: $0)
		}
		if let output
		{
			try FileManager.default.createDirectory(
				at: output,
				withIntermediateDirectories: true
			)
		}
		let suite = "UIPolishEvidence.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let controller = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		let split = controller.paneController.split
		let conversation = try #require(
			split.splitViewItems[1].viewController.children.first as? ConversationViewController
		)
		let thread = try #require(
			ThreadSummary(json: [
				"id": "polish-preview",
				"name": "Polish the Codex GUI",
				"cwd": "/tmp/codex-gui",
			])
		)
		let model = try #require(
			ModelOption(json: [
				"model": "synthetic-sol",
				"displayName": "Sol (UI fixture)",
				"isDefault": true,
				"supportedReasoningEfforts": [["reasoningEffort": "high"]],
			])
		)
		let entries = [
			ConversationEntry(
				id: "user",
				kind: .user,
				title: "You",
				body:
				"Polish the Codex GUI to match the ChatGPT desktop app.\n"
					+ "Keep the native controls, make the chat easier to read, and "
					+ "refine the composer."
			),
			ConversationEntry(
				id: "answer",
				kind: .agent,
				title: "Codex",
				body:
				"The interface now has a quieter sidebar, a compact title "
					+ "bar, and a rounded composer.\n\n- Messages use a centered "
					+ "reading column.\n- User messages appear in rounded "
					+ "bubbles.\n- Changes and context are grouped into cards.\n\n"
					+ "The interface uses native AppKit controls:\n\n```swift\nlet "
					+ "composer = DesktopSurface(\n  DesktopTheme.input, "
					+ "cornerRadius: 22)\n```"
			),
		]
		let snapshot = ConversationSnapshot(
			projectPath: "/tmp/codex-gui",
			threads: [thread],
			selectedThreadID: thread.id,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [ChangeFile(
				path: "Interface.swift",
				status: "Modified"
			)],
			diff: "@@ -1 +1 @@\n-// Previous interface\n+// Refined native interface\n",
			draft: "",
			canSend: true,
			accountDescription: "Synthetic UI fixture",
			backendDescription: "Synthetic UI fixture",
			executionState: .ready,
			statusMessage: nil,
			models: [model],
			selectedModelID: model.id,
			selectedEffort: "high",
			pendingInteractions: [],
			recentProjects: [],
			pinnedTasks: [thread]
		)
		controller.renderSnapshot(snapshot)
		controller.showWindow(nil)
		defer
		{
			window.orderOut(nil)
		}
		await conversation.waitForRendering()
		for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)]
		{
			window.appearance = NSAppearance(named: appearance)
			for size in [NSSize(
				width: 1200,
				height: 760
			), NSSize(
				width: 800,
				height: 500
			)]
			{
				window.setFrame(
					NSRect(
						origin: window.frame.origin,
						size: size
					),
					display: true
				)
				window.layoutIfNeeded()
				try await Task.sleep(for: .milliseconds(150))
				window.layoutIfNeeded()
				#expect(window.frame.size == size)
				let content = try #require(window.contentView)
				let accountFrame = controller.statusButton.convert(
					controller.statusButton.bounds,
					to: content
				)
				#expect(abs(accountFrame.midX - 26) < 1)
				#expect(abs(accountFrame.minY - 9.5) < 1)
				#expect(accountFrame.size == NSSize(
					width: 36,
					height: 36
				))
				let workspaceFrame = split.view.convert(
					split.view.bounds,
					to: content
				)
				#expect(workspaceFrame.minX == 53)
				#expect(abs(workspaceFrame.maxX - (content.bounds.maxX - 4)) < 0.5)
				#expect(abs(workspaceFrame.minY - (content.bounds.minY + 4)) < 0.5)
				#expect(window.toolbar?.items.contains
				{
					$0.itemIdentifier.rawValue == "status"
				} == false)
				#expect(split.splitViewItems[2].isCollapsed == (size.width == 800))
				#expect(split.splitViewItems[1].viewController.view.frame.width >= 360)
				SplitPaneLayoutChecks.verifyVisiblePanesFit(split)
				if let output
				{
					let content = try #require(window.contentView)
					content.displayIfNeeded()
					let bitmap = try #require(content
						.bitmapImageRepForCachingDisplay(in: content.bounds))
					content.cacheDisplay(
						in: content.bounds,
						to: bitmap
					)
					let png = try #require(bitmap.representation(
						using: .png,
						properties: [:]
					))
					try png.write(
						to: output
							.appendingPathComponent(
								"\(name)-\(Int(size.width))x\(Int(size.height)).png"
							)
					)
				}
			}
		}
		let navigationItem = try #require(window.toolbar?.items.first
		{
			$0.itemIdentifier == MainWindowController.ToolbarItem.navigationControls
		})
		let navigationHost = try #require(navigationItem.view)
		let sidebarButton = try #require(navigationHost.subviews
			.flatMap
			{
				$0.subviews
			}.compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.toolTip == "Toggle sidebar"
			})
		let navigationButtons = navigationHost.subviews.flatMap
		{
			$0.subviews
		}
		.compactMap
		{
			$0 as? NSButton
		}
		#expect(navigationButtons.count == 3)
		#expect(!navigationButtons.contains
		{
			$0.toolTip == "New chat"
		})
		#expect(abs(navigationHost.bounds.width - 127) < 0.5)
		for (index, button) in navigationButtons.enumerated()
		{
			let frame = button.convert(
				button.bounds,
				to: navigationHost
			)
			#expect(abs(frame.minX - (CGFloat(index) * 34 - 1)) < 0.5)
			#expect(frame.size == NSSize(
				width: 28,
				height: 28
			))
		}
		#expect(sidebarButton.isEnabled)
		let navigationWidth = split.splitViewItems[0].viewController.view.frame.width
		sidebarButton.performClick(nil)
		window.layoutIfNeeded()
		#expect(split.splitViewItems[0].isCollapsed)
		#expect(controller.statusButton.window === window)
		#expect(!controller.statusButton.isHiddenOrHasHiddenAncestor)
		sidebarButton.performClick(nil)
		window.layoutIfNeeded()
		#expect(!split.splitViewItems[0].isCollapsed)
		#expect(abs(split.splitViewItems[0].viewController.view.frame.width - navigationWidth) < 1)
	}
}
