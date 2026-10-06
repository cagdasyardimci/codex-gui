import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabSourcesIntegrationTests
{
	@Test func repeatedSourcesOpeningReusesTabAndAttachmentView() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let sources = try sourcesController()
		tabs.showSources(sources)
		let tabID = try #require(tabs.sourcesTabID)
		let scroll = try #require(sources.view as? NSScrollView)
		let document = try #require(scroll.documentView)
		tabs.showSources(sources)
		#expect(tabs.tabCount == 1)
		#expect(tabs.sourcesTabID == tabID)
		#expect(tabs.isSourcesSelected)
		#expect(sources.parent === tabs)
		#expect(scroll.documentView === document)
		#expect(button(
			"Sources 1",
			in: tabs.tabBarView
		)?.title == "Sources")
		try captureIfRequested(tabs)
	}

	@Test(arguments: [false, true])
	func sourcesAndChangesKeepSeparateTabsInEitherOpeningOrder(sourcesFirst: Bool) throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let sources = try sourcesController()
		let changes = NSViewController()
		changes.view = NSView()
		if sourcesFirst
		{
			tabs.showSources(sources)
			tabs.showChanges(changes)
		}
		else
		{
			tabs.openNewTab()
			tabs.showChanges(changes)
			tabs.showSources(sources)
		}
		let sourcesID = try #require(tabs.sourcesTabID)
		let changesID = try #require(tabs.changesTabID)
		#expect(sourcesID != changesID)
		#expect(tabs.tabCount == 2)
		#expect(sources.parent === tabs)
		#expect(changes.parent === tabs)
		#expect(tabs.isSourcesSelected == !sourcesFirst)
		#expect(tabs.isChangesSelected == sourcesFirst)
		#expect(sources.view.isHidden == sourcesFirst)
		#expect(changes.view.isHidden == !sourcesFirst)
		tabs.showSources(sources)
		#expect(tabs.tabCount == 2)
		#expect(tabs.isSourcesSelected)
		#expect(!sources.view.isHidden)
		#expect(changes.view.isHidden)
	}

	@Test func blankChangesAndConversationSelectionsPreserveSourcesContent() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let sources = try sourcesController()
		tabs.showSources(sources)
		let sourceID = try #require(tabs.sourcesTabID)
		let scroll = try #require(sources.view as? NSScrollView)
		let document = try #require(scroll.documentView)
		tabs.openNewTab()
		#expect(!tabs.isSourcesSelected)
		#expect(sources.view.isHidden)
		try #require(button(
			"Sources 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isSourcesSelected)
		#expect(!sources.view.isHidden)
		let changes = NSViewController()
		changes.view = NSView()
		tabs.showChanges(changes)
		#expect(tabs.isChangesSelected)
		#expect(sources.view.isHidden)
		try #require(button(
			"Sources 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isSourcesSelected)
		tabs.setExpanded(true)
		try #require(button(
			"Chat: New chat",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isConversationSelected)
		#expect(!tabs.isSourcesSelected)
		#expect(sources.view.isHidden)
		try #require(button(
			"Sources 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(!tabs.isConversationSelected)
		#expect(tabs.isSourcesSelected)
		#expect(tabs.sourcesTabID == sourceID)
		#expect(scroll.documentView === document)
		#expect(!sources.view.isHidden)
	}

	@Test func closingSourcesTabKeepsInventoryAndReopeningCreatesNewTab() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let sources = try sourcesController()
		let records = sources.sources.records
		tabs.showSources(sources)
		let oldID = try #require(tabs.sourcesTabID)
		let scroll = try #require(sources.view as? NSScrollView)
		let document = try #require(scroll.documentView)
		try #require(button(
			"Close tab 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.sourcesTabID == nil)
		#expect(tabs.tabCount == 0)
		#expect(sources.sources.records == records)
		tabs.showSources(sources)
		#expect(tabs.sourcesTabID != nil)
		#expect(tabs.sourcesTabID != oldID)
		#expect(tabs.tabCount == 1)
		#expect(tabs.isSourcesSelected)
		#expect(sources.parent === tabs)
		#expect(scroll.documentView === document)
		#expect(sources.sources.records == records)
	}

	@Test func inspectorRejectsStaleOwnerAndRemovesSourcesTabWhenChatChanges() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		var snapshot = snapshot()
		let presentation = PinnedSummaryPresentation(
			snapshot,
			ownerIdentity: "fixture"
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		let sources = try sourcesController(owner: presentation.owner)
		inspector.conversationSources = sources
		let request = ContextPanelRequest(
			owner: presentation.owner,
			destination: .sources
		)
		#expect(inspector.openSourcesInToolTab(request))
		#expect(inspector.isShowingTools)
		#expect(inspector.toolsTabs.isSourcesSelected)
		#expect(!inspector.isShowingDetails)
		#expect(sources.parent === inspector.toolsTabs)
		#expect(inspector.openSourcesInToolTab(request))
		#expect(inspector.toolsTabs.tabCount == 1)
		#expect(!inspector.openSourcesInToolTab(ContextPanelRequest(
			owner: presentation.owner,
			destination: .sources,
			recordID: "missing-record"
		)))
		snapshot = self.snapshot(thread: "another-chat")
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				ownerIdentity: "fixture"
			),
			visible: true
		)
		#expect(inspector.toolsTabs.sourcesTabID == nil)
		#expect(!inspector.openSourcesInToolTab(request))
		#expect(inspector.toolsTabs.sourcesTabID == nil)
	}

	@Test func viewAllButtonOpensTheSourcesToolTab() async throws
	{
		_ = NSApplication.shared
		let suite = "SourcesTabDispatch.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let directory = FileManager.default.temporaryDirectory.standardizedFileURL
		let service = WorkspaceCodexService(
			directory: directory,
			threadID: "sources-dispatch"
		)
		let session = UUID()
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(reference: WorkspaceLifecycleOwnerReference(
				owner: .source(sessionID: session),
				workspace: WorkspaceIdentity(
					sessionID: session,
					canonicalCheckoutPath: directory.path
				)
			)),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: LocalStorage(defaults: defaults)
			)
		)
		let state = WorkspaceTestFixture(store: store)
		defer
		{
			state.shutdown()
		}
		await state.inputs.connect()
		let controller = MainWindowController(
			store: store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		defer
		{
			controller.window?.close()
		}
		let snapshot = state.currentSnapshot
		controller.renderPinnedSummary(
			snapshot,
			target: WorkspaceIntentTarget(
				store: store,
				snapshot: snapshot
			)
		)
		let viewAll = try #require(button(
			"View all",
			in: controller.inspector.summary.view
		))
		#expect(viewAll.isEnabled)
		viewAll.performClick(nil)
		#expect(controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.isSourcesSelected)
		#expect(!controller.inspector.isShowingDetails)
		#expect(controller.inspector.conversationSources?.parent === controller.inspector.toolsTabs)
	}

	private func snapshot(thread: String = "sources-chat") -> ConversationSnapshot
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		model.conversations.selectedConversation = .thread(thread)
		return WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
	}

	private func sourcesController(owner: FeaturePresentationOwner? = nil) throws
		-> ConversationSourcesViewController
	{
		let image = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/sources-fixture/attached-image.png"],
			id: "image"
		))
		return ConversationSourcesViewController(
			owner: owner ?? FeaturePresentationOwner(snapshot()),
			sources: ConversationLocalSources(entries: [ConversationEntry(
				id: "turn:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [image]
			)])
		)
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func captureIfRequested(_ tabs: ToolsTabViewController) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_SOURCES_QA_DIR"]
		else
		{
			return
		}
		let host = NSViewController()
		host.view = NSView()
		let stack = AppKitLayout.verticalStack(
			[tabs.tabBarView, tabs.view],
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: host.view,
			inset: 12
		)
		tabs.tabBarView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		tabs.tabBarView.heightAnchor.constraint(equalToConstant: 28).isActive = true
		tabs.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		tabs.view.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 600
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = host
		window.setContentSize(NSSize(
			width: 900,
			height: 600
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		host.view.layoutSubtreeIfNeeded()
		let destination = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: destination,
			withIntermediateDirectories: true
		)
		try AppTestPNGWriter.write(
			host.view,
			to: destination.appendingPathComponent("sources-tools-tab.png")
		)
	}
}
