import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationHistoryWindowTests
{
	@Test func loadingHistoryThenSwitchingThreadsRemovesRetiredViews() async throws
	{
		_ = NSApplication.shared
		let defaults = try IsolatedUserDefaultsFixture(prefix: "ConversationReuseTests")
		defer
		{
			defaults.cleanup()
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults.defaults))
		defer
		{
			state.shutdown()
		}
		let main = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(main.window)
		defer
		{
			window.close()
		}
		let split = main.paneController.split
		let controller = try #require(
			split.splitViewItems[1].viewController.children.compactMap
			{
				$0 as? ConversationViewController
			}.first
		)
		split.view.layoutSubtreeIfNeeded()
		let collection = try #require(findCollection(in: controller.view))
		var history = (0 ..< 160).map
		{
			ConversationEntry(
				id: "history-\($0)",
				kind: .agent,
				title: "Codex",
				body: "## Earlier message \($0)\n\n"
					+ String(
						repeating: "Readable conversation history. ",
						count: 8
					) + "\n\n"
					+ markdownHistoryBlock(index: $0)
			)
		}
		history.append(
			ConversationEntry(
				id: "long-tail",
				kind: .agent,
				title: "Codex",
				body: String(
					repeating: "Final reading marker\n",
					count: 60
				)
			)
		)
		controller.render(snapshot(
			[],
			thread: "history"
		))
		await controller.waitForRendering()
		controller.render(snapshot(
			history,
			thread: "history"
		))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()
		#expect(collection.numberOfItems(inSection: 0) == history.count)
		#expect(!collection.visibleItems().isEmpty)
		let layout = try #require(collection.collectionViewLayout)
		var previousBottom: CGFloat = 0
		for index in history.indices
		{
			let attributes = try #require(layout.layoutAttributesForItem(at: IndexPath(
				item: index,
				section: 0
			)))
			#expect(attributes.frame.height.isFinite && attributes.frame.height > 0)
			#expect(attributes.frame.minY >= previousBottom)
			previousBottom = attributes.frame.maxY
		}
		#expect(layout.collectionViewContentSize.height >= previousBottom)
		controller.render(snapshot(
			[],
			thread: "task"
		))
		await controller.waitForRendering()
		controller.render(
			snapshot(
				[
					ConversationEntry(
						id: "task",
						kind: .agent,
						title: "Codex",
						body: "Synthetic task-control fixture."
					)
				],
				thread: "task"
			)
		)
		await controller.waitForRendering()
		let taskCollection = try #require(findCollection(in: controller.view))
		taskCollection.layoutSubtreeIfNeeded()
		#expect(collection.superview == nil)
		#expect(collection.dataSource == nil)
		#expect(collection.delegate == nil)
		let visibleTexts = textViews(in: taskCollection).filter
		{
			!$0.isHiddenOrHasHiddenAncestor
		}
		.map(\.string)
		#expect(visibleTexts == ["Synthetic task-control fixture."])
		#expect(taskCollection.numberOfItems(inSection: 0) == 1)
		#expect(taskCollection.accessibilityLabel() == "Conversation messages and activity")

		controller.render(
			snapshot(
				[
					ConversationEntry(
						id: "task",
						kind: .agent,
						title: "Codex",
						body: "Updated task output"
					),
					ConversationEntry(
						id: "more",
						kind: .agent,
						title: "Codex",
						body: "More task output"
					),
				],
				thread: "task"
			)
		)
		await controller.waitForRendering()
		#expect(findCollection(in: controller.view) === taskCollection)
		#expect(taskCollection.numberOfItems(inSection: 0) == 2)
	}

	private func markdownHistoryBlock(index: Int) -> String
	{
		switch index % 4
		{
		case 0: "- list item\n  - nested item with **bold** text"
		case 1: "> quoted history with `inline code` and 😀"
		case 2: "| Name | Value |\n| :--- | ---: |\n| earlier result | 42 |"
		default: "~~~text\n  exact code 😀\n~~~"
		}
	}

	private func textViews(in view: NSView) -> [NSTextView]
	{
		if let text = view as? NSTextView
		{
			return [text]
		}
		return view.subviews.flatMap
		{
			textViews(in: $0)
		}
	}

	private func findCollection(in view: NSView) -> NSCollectionView?
	{
		if let collection = view as? NSCollectionView
		{
			return collection
		}
		return view.subviews.lazy.compactMap
		{
			findCollection(in: $0)
		}.first
	}

	private func snapshot(
		_ entries: [ConversationEntry],
		thread: String
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/layout",
			threads: [],
			selectedThreadID: thread,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
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
	}
}
