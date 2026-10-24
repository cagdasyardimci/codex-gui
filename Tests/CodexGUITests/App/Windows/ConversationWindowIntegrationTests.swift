import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationWindowIntegrationTests
{
	@Test(arguments: [false, true])
	func summaryToggleReleasesPaneAndRecentersPopulatedConversation(
		readingEarlierMessages: Bool
	) async throws
	{
		_ = NSApplication.shared
		let suite = "SummaryToggleLayout.\(UUID())"
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
		defer
		{
			window.close()
		}
		window.setContentSize(NSSize(
			width: 1512,
			height: 876
		))
		controller.paneController.setSidebarCollapsed(true)
		let presentation = snapshot(draft: "Preserve this draft")
		controller.renderSnapshot(presentation)
		await controller.conversation.waitForRendering()
		controller.paneController.didPresentWindow()
		window.layoutIfNeeded()
		let conversation = controller.conversation
		await conversation.transcript.widthChangeRestoreTask?.value
		if readingEarlierMessages
		{
			let clip = conversation.transcript.conversationScrollView.contentView
			clip.scroll(to: NSPoint(
				x: 0,
				y: 120
			))
			conversation.transcript.conversationScrollView.reflectScrolledClipView(clip)
			conversation.transcript.readingPositionChanged()
			#expect(!conversation.transcript.isNearBottom)
		}
		let initialComposer = conversation.view.convert(
			conversation.composerSurface.bounds,
			from: conversation.composerSurface
		)
		let initialPaneWidth = conversation.view.bounds.width
		let summaryWidth = controller.paneController.reviewViewportWidth
		#expect(abs(summaryWidth - InspectorViewController.summaryPaneWidth) < 1)
		let scrollOrigin = conversation.transcript.conversationScrollView.contentView.bounds.origin

		for hidden in [true, false, true, false]
		{
			controller.togglePinnedSummary()
			window.layoutIfNeeded()
			conversation.transcript.collectionView.layoutSubtreeIfNeeded()
			await conversation.transcript.widthChangeRestoreTask?.value
			#expect(controller.paneController.isReviewCollapsed == hidden)
			#expect(controller.summaryToggleButton.state == (hidden ? .off : .on))
			let composer = conversation.view.convert(
				conversation.composerSurface.bounds,
				from: conversation.composerSurface
			)
			#expect(abs(composer.width - initialComposer.width) < 1)
			#expect(abs(composer.midX - conversation.view.bounds.midX) < 1)
			if hidden
			{
				#expect(conversation.view.bounds.width > initialPaneWidth + summaryWidth - 1)
				#expect(abs(composer.minX - initialComposer.minX - summaryWidth / 2) < 1)
			}
			else
			{
				#expect(abs(composer.minX - initialComposer.minX) < 1)
				#expect(abs(controller.paneController.reviewViewportWidth - summaryWidth) < 1)
			}
			for index in conversation.transcript.displayedRows.indices
			{
				let attributes = try #require(conversation.transcript.collectionView
					.layoutAttributesForItem(
						at: IndexPath(
							item: index,
							section: 0
						)
					))
				let row = conversation.view.convert(
					attributes.frame,
					from: conversation.transcript.collectionView
				)
				#expect(abs(row.minX - composer.minX) < 1)
				#expect(abs(row.maxX - composer.maxX) < 1)
			}
			#expect(conversation.composer.string == presentation.draft)
			#expect(abs(conversation.transcript.conversationScrollView.contentView.bounds.minY
					- scrollOrigin.y) < 1)
		}
	}

	@Test func fullWindowSummaryUsesCardWidthWithoutOverwritingDetailGeometry() async throws
	{
		_ = NSApplication.shared
		let suite = "ConversationColumnHost.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let store = WindowLayoutStore(defaults: defaults)
		store.layout = WindowLayout(
			frame: CGRect(
				x: 0,
				y: 0,
				width: 1512,
				height: 876
			),
			navigationWidth: 260,
			reviewWidth: 342,
			reviewCollapsed: false,
			paneGeometryVersion: WindowPaneLayout.version,
			reviewVisibility: .expanded
		)
		let conversation = ConversationViewController()
		let inspector = InspectorViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: conversation,
			inspector: inspector,
			layoutStore: store
		)
		let chrome = WindowChromeViewController(
			split: panes.split,
			accountButton: NSButton()
		)
		let window = NSWindow(
			contentRect: CGRect(
				x: 0,
				y: 0,
				width: 1512,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = chrome
		defer
		{
			window.close()
		}
		panes.restoreLayout(in: window)
		// Screen fitting is independent of this synthetic screenshot-sized viewport.
		window.setContentSize(NSSize(
			width: 1512,
			height: 876
		))
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture"
		))
		model.conversations.selectedConversation = .thread("chat")
		let presentation = PinnedSummaryPresentation(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			ownerIdentity: "fixture",
			sections: ContextSummarySections()
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		conversation.render(snapshot())
		await conversation.waitForRendering()
		panes.didPresentWindow()
		window.layoutIfNeeded()
		let composer = chrome.view.convert(
			conversation.composerSurface.bounds,
			from: conversation.composerSurface
		)
		let conversationFrame = chrome.view.convert(
			conversation.view.bounds,
			from: conversation.view
		)
		#expect(abs(composer.width - ConversationFlowLayout.maximumContentWidth) < 1)
		#expect(abs(composer.midX - conversationFrame.midX) < 0.5)
		for index in conversation.transcript.displayedRows.indices
		{
			let attributes = try #require(conversation.transcript.collectionView
				.layoutAttributesForItem(
					at: IndexPath(
						item: index,
						section: 0
					)
				))
			let row = chrome.view.convert(
				attributes.frame,
				from: conversation.transcript.collectionView
			)
			#expect(abs(row.minX - composer.minX) < 0.5)
			#expect(abs(row.maxX - composer.maxX) < 0.5)
		}
		#expect(abs(panes.reviewViewportWidth - 308) < 0.5)
		let summaryBox = try #require(inspector.summary.view.superview?.superview?.superview)
		let summary = chrome.view.convert(
			summaryBox.bounds,
			from: summaryBox
		)
		#expect(abs(summary.width - 300) < 1)
		let inspectorFrame = chrome.view.convert(
			inspector.view.bounds,
			from: inspector.view
		)
		#expect(abs(summary.minX - inspectorFrame.minX) < 0.5)
		#expect(abs(inspectorFrame.maxX - summary.maxX - 8) < 0.5)
		// The card's first painted pixel is 2399–2400 in the 2x reference image.
		#expect(abs(summary.minX - 1199.5) <= 0.5)
		let splitFrame = chrome.view.convert(
			panes.split.view.bounds,
			from: panes.split.view
		)
		#expect(abs(chrome.view.bounds.maxY - splitFrame.maxY - 3.5) < 0.5)
		panes.saveLayout()
		#expect(store.layout?.reviewWidth == 342)
		inspector.renderSummary(
			presentation,
			visible: false
		)
		window.layoutIfNeeded()
		#expect(panes.isReviewCollapsed)
		panes.saveLayout()
		#expect(store.layout?.reviewVisibility == .expanded)
		#expect(store.layout?.reviewWidth == 342)
		#expect(inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		)))
		window.layoutIfNeeded()
		#expect(abs(panes.reviewViewportWidth - 342) < 0.5)
		inspector.showSummary()
		window.layoutIfNeeded()
		#expect(panes.isReviewCollapsed)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		window.layoutIfNeeded()
		#expect(abs(panes.reviewViewportWidth - 308) < 0.5)
		inspector.showToolsPane()
		window.layoutIfNeeded()
		#expect(panes.reviewViewportWidth >= WindowPaneLayout.toolsMinimumWidth - 1)
		let selectedTab = inspector.toolsTabs.selectedTabID
		inspector.renderSummary(
			presentation,
			visible: false
		)
		window.layoutIfNeeded()
		#expect(!panes.isReviewCollapsed)
		#expect(inspector.toolsTabs.selectedTabID == selectedTab)
		inspector.closeToolsPane()
		window.layoutIfNeeded()
		#expect(panes.isReviewCollapsed)
		var otherModel = model
		otherModel.conversations.selectedConversation = .thread("other-chat")
		inspector.renderSummary(
			PinnedSummaryPresentation(WorkspaceSelectors.snapshot(
				model: otherModel,
				now: .distantPast
			)),
			visible: true
		)
		window.layoutIfNeeded()
		#expect(abs(panes.reviewViewportWidth - 308) < 0.5)
		panes.setGitReviewFocused(true)
		chrome.setGitReviewFocused(true)
		window.layoutIfNeeded()
		let focusedSplit = chrome.view.convert(
			panes.split.view.bounds,
			from: panes.split.view
		)
		#expect(abs(focusedSplit.maxY - chrome.view.bounds.maxY) < 0.5)
		#expect(abs(focusedSplit.width - chrome.view.bounds.width) < 0.5)
		panes.setGitReviewFocused(false)
		chrome.setGitReviewFocused(false)
		window.layoutIfNeeded()
		for width: CGFloat in [800, 1512]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 876
			))
			window.layoutIfNeeded()
			let composerFrame = chrome.view.convert(
				conversation.composerSurface.bounds,
				from: conversation.composerSurface
			)
			let paneFrame = chrome.view.convert(
				conversation.view.bounds,
				from: conversation.view
			)
			#expect(abs(composerFrame.midX - paneFrame.midX) < 0.5)
			#expect(composerFrame.width <= 736.5)
		}
		inspector.showToolsPane()
		panes.toggleToolsExpanded()
		// Completion belongs to the transition, not a fixed polling budget.
		await panes.waitForToolsTransition()
		try #require(!panes.isAnimatingToolsExpansion)
		try #require(findButton(
			in: inspector.toolsTabs.tabBarView,
			title: "Chat: New chat"
		)).performClick(nil)
		try #require(panes.isShowingExpandedConversation)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		inspector.showSummaryBesideExpandedConversation()
		window.layoutIfNeeded()
		let expandedWidthWithSummary = conversation.view.bounds.width
		for visible in [false, true]
		{
			inspector.renderSummary(
				presentation,
				visible: visible
			)
			window.layoutIfNeeded()
			#expect(!panes.isReviewCollapsed)
			#expect(panes.isShowingExpandedConversation)
			#expect(inspector.isSummaryBesideExpandedConversation == visible)
			let expectedWidth = expandedWidthWithSummary
				+ (visible ? 0 : InspectorViewController.summaryPaneWidth)
			#expect(abs(conversation.view.bounds.width - expectedWidth) < 1)
		}
	}

	@Test func changesPaneResizesExistingAndStreamedItems() async throws
	{
		_ = NSApplication.shared
		let defaults = try #require(UserDefaults(suiteName: "ConversationLayoutTests.\(UUID())"))
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let windowController = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(windowController.window)
		let split = windowController.paneController.split
		let controller = try #require(
			split.splitViewItems[1].viewController.children.compactMap
			{
				$0 as? ConversationViewController
			}.first
		)
		let collection = try #require(findCollection(in: controller.view))
		var entries = (0 ..< 30).map
		{
			ConversationEntry(
				id: "message-\($0)",
				kind: .agent,
				title: "Codex",
				body: String(
					repeating: "Streamed message content ",
					count: 8
				)
			)
		}
		split.view.layoutSubtreeIfNeeded()
		controller.render(integrationSnapshot(entries))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()

		for collapsed in [true, false, true, false]
		{
			split.splitViewItems[2].isCollapsed = collapsed
			split.view.layoutSubtreeIfNeeded()
			collection.layoutSubtreeIfNeeded()
			for index in [0, entries.count - 1]
			{
				let attributes = try #require(
					collection.layoutAttributesForItem(at: IndexPath(
						item: index,
						section: 0
					))
				)
				#expect(attributes.frame.maxX <= collection.bounds.width - 8)
			}
			entries[0].body += "\nMore output"
			entries.append(
				ConversationEntry(
					id: "message-\(entries.count)",
					kind: .agent,
					title: "Codex",
					body: "More output"
				)
			)
			controller.render(integrationSnapshot(entries))
			await controller.waitForRendering()
			collection.layoutSubtreeIfNeeded()
		}
	}

	@Test func interruptedTaskShowsStoppedAcrossViews() throws
	{
		_ = NSApplication.shared
		let thread = try #require(
			ThreadSummary(json: [
				"id": "replay",
				"name": "Interrupted work",
				"cwd": "/tmp/replay",
			])
		)
		var stopped = integrationSnapshot(
			[],
			executionState: .stopped,
			threads: [thread]
		)
		stopped.activeThreadID = "replay"
		stopped.activeExecutionState = .stopped
		let conversation = ConversationViewController()
		_ = conversation.view
		conversation.render(stopped)
		let stateLabel = try #require(findLabel(
			in: conversation.view,
			label: "Execution state"
		))
		let stopButton = try #require(findButton(
			in: conversation.view,
			title: "Stop"
		))
		#expect(stateLabel.stringValue == "Stopped")
		#expect(!stopButton.isEnabled)

		let navigation = NavigationViewController()
		_ = navigation.view
		navigation.render(stopped)
		let projectActions = try #require(findButton(
			in: navigation.view,
			title: "Project Actions"
		))
		let table = try #require(findTable(in: navigation.view))
		let row = try #require(table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		))
		#expect(projectActions.toolTip == "Add new project")
		#expect(row.accessibilityLabel()?.contains("Stopped task") == true)
	}

	private func snapshot(draft: String = "") -> ConversationSnapshot
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
			draft: draft,
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

	private func findButton(
		in view: NSView,
		title: String
	) -> NSButton?
	{
		if let button = view as? NSButton,
			button.title == title || button.accessibilityLabel() == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				in: $0,
				title: title
			)
		}.first
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

	private func findTable(in view: NSView) -> NSTableView?
	{
		if let table = view as? NSTableView
		{
			return table
		}
		return view.subviews.lazy.compactMap
		{
			findTable(in: $0)
		}.first
	}

	private func findLabel(
		in view: NSView,
		label: String
	) -> NSTextField?
	{
		if let textField = view as? NSTextField, textField.accessibilityLabel() == label
		{
			return textField
		}
		return view.subviews.lazy.compactMap
		{
			findLabel(
				in: $0,
				label: label
			)
		}.first
	}

	private func integrationSnapshot(
		_ entries: [ConversationEntry],
		executionState: ExecutionState = .running,
		threads: [ThreadSummary] = [],
		selectedThreadID: String = "replay"
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: threads,
			selectedThreadID: selectedThreadID,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: executionState,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
