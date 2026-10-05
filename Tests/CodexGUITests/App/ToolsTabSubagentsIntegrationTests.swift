import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabSubagentsIntegrationTests
{
	@Test func workingTimersStopWhenHiddenAndResumeWhenTheirTabReturns()
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let presentation = PinnedSummaryPresentation(
			snapshot(),
			ownerIdentity: "timer-fixture"
		)
		let startedAt = Date(timeIntervalSince1970: 1000)
		let entry = ConversationEntry(
			id: "working-agent",
			kind: .tool,
			title: "Subagent",
			body: "",
			activity: .subagent(CodexSubagentActivity(
				kind: "started",
				threadID: "child",
				startedAt: startedAt
			))
		)
		let agents = SubagentsViewController(
			owner: presentation.owner,
			subagents: ConversationSubagents(entries: [entry]),
			now:
			{
				startedAt
			}
		)

		tabs.showSubagents(agents)
		#expect(agents.isRefreshingTimeLabels)
		tabs.setContentVisible(false)
		#expect(!agents.isRefreshingTimeLabels)
		tabs.setContentVisible(true)
		#expect(agents.isRefreshingTimeLabels)
		tabs.showSources(controller())
		#expect(!agents.isRefreshingTimeLabels)
		tabs.showSubagents(agents)
		#expect(agents.isRefreshingTimeLabels)
		tabs.removeSubagentsTab()
		#expect(!agents.isRefreshingTimeLabels)
		#expect(agents.parent == nil)
	}

	@Test func featureTabsRemainDistinctAndReuseTheirOwnContent() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let agents = controller()
		let sources = controller()
		let changes = controller()
		tabs.showSubagents(agents)
		let agentsID = try #require(tabs.subagentsTabID)
		tabs.showSources(sources)
		tabs.showChanges(changes)
		#expect(tabs.tabCount == 3)
		let sourcesID = try #require(tabs.sourcesTabID)
		let changesID = try #require(tabs.changesTabID)
		#expect(Set([agentsID, sourcesID, changesID]).count == 3)
		#expect(agents.view.isHidden)
		#expect(sources.view.isHidden)
		#expect(!changes.view.isHidden)

		try #require(button(
			"Subagents 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isSubagentsSelected)
		#expect(!agents.view.isHidden)
		#expect(changes.view.isHidden)
		tabs.showSubagents(agents)
		#expect(tabs.tabCount == 3)
		#expect(tabs.subagentsTabID == agentsID)
	}

	@Test func closingSubagentsSelectsRemainingTabAndDetachesContent() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let agents = controller()
		tabs.showSources(controller())
		tabs.showSubagents(agents)
		var closedCount = 0
		tabs.onSubagentsTabClosed =
		{
			closedCount += 1
		}
		try #require(button(
			"Close tab 2",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.tabCount == 1)
		#expect(tabs.subagentsTabID == nil)
		#expect(tabs.isSourcesSelected)
		#expect(agents.parent == nil)
		#expect(closedCount == 1)
	}

	@Test func blankTabReuseAndControllerReplacementDoNotLeakChildren()
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		let blankID = tabs.selectedTabID
		let first = controller()
		tabs.showSubagents(first)
		#expect(tabs.subagentsTabID == blankID)
		let second = controller()
		tabs.showSubagents(second)
		#expect(first.parent == nil)
		#expect(second.parent === tabs)
		#expect(tabs.tabCount == 1)
		tabs.setExpanded(true)
		button(
			"Chat: New chat",
			in: tabs.tabBarView
		)?.performClick(nil)
		#expect(second.view.isHidden)
		tabs.showSubagents(second)
		#expect(!second.view.isHidden)
		tabs.removeSubagentsTab()
		#expect(tabs.tabCount == 0)
		#expect(tabs.subagentsTabID == nil)
	}

	@Test func inspectorRejectsStaleOwnerAndRemovesSubagentsWhenChatChanges() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let presentation = PinnedSummaryPresentation(
			snapshot(),
			ownerIdentity: "fixture"
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		let agents = SubagentsViewController(
			owner: presentation.owner,
			subagents: ConversationSubagents(entries: fixtureEntries())
		)
		inspector.conversationSubagents = agents
		let request = ContextPanelRequest(
			owner: presentation.owner,
			destination: .subagents
		)
		#expect(inspector.openSubagentsInToolTab(request))
		#expect(inspector.toolsTabs.isSubagentsSelected)
		#expect(inspector.isShowingTools)
		#expect(!inspector.isShowingDetails)
		#expect(agents.parent === inspector.toolsTabs)
		#expect(inspector.openSubagentsInToolTab(request))
		#expect(inspector.toolsTabs.tabCount == 1)
		#expect(!inspector.openSubagentsInToolTab(ContextPanelRequest(
			owner: presentation.owner,
			destination: .subagents,
			recordID: "unknown-agent"
		)))
		try captureIfRequested(inspector.toolsTabs)
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot(thread: "another-chat"),
				ownerIdentity: "fixture"
			),
			visible: true
		)
		#expect(inspector.toolsTabs.subagentsTabID == nil)
		#expect(agents.parent == nil)
		#expect(!inspector.openSubagentsInToolTab(request))
	}

	@Test func summaryAndTranscriptOpenTheSameSubagentsTab() async throws
	{
		_ = NSApplication.shared
		let suite = "SubagentsTabDispatch.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let directory = FileManager.default.temporaryDirectory.standardizedFileURL
		let service = WorkspaceCodexService(
			directory: directory,
			threadID: "subagents-dispatch"
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
		var model = store.model
		let key = model.conversations.selectedConversation
		var content = model.conversations.content[key] ?? ConversationContentModel()
		content.entries = fixtureEntries()
		model.conversations.content[key] = content
		let snapshot = WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
		controller.renderPinnedSummary(
			snapshot,
			target: WorkspaceIntentTarget(
				store: store,
				snapshot: snapshot
			)
		)
		let viewAll = try #require(button(
			"12 done · 1 running. Subagents in loaded conversation history",
			in: controller.inspector.summary.view
		))
		#expect(viewAll.isEnabled)
		viewAll.performClick(nil)
		#expect(controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.isSubagentsSelected)
		#expect(!controller.inspector.isShowingDetails)
		#expect(controller.inspector.conversationSubagents?.parent === controller.inspector
			.toolsTabs)
		let tabID = controller.inspector.toolsTabs.subagentsTabID
		controller.conversation.onOpenSubagents?()
		#expect(controller.inspector.toolsTabs.subagentsTabID == tabID)
		#expect(controller.inspector.toolsTabs.tabCount == 1)
	}

	private func fixtureEntries() -> [ConversationEntry]
	{
		let names = [
			"app_client",
			"conversation",
			"features",
			"application",
			"runtime",
			"reducers",
			"conversation_ui",
			"composer_execution",
			"tests_application",
			"tests_ui",
			"review",
			"integration",
			"active_agent",
		]
		return names.enumerated().map
		{
			index, name in
			ConversationEntry(
				id: "agent-\(index)",
				kind: .tool,
				title: "Subagent",
				body: "",
				activity: .subagent(CodexSubagentActivity(json: [
					"kind": index == 12 ? "started" : "completed",
					"agentThreadId": "agent-\(index)",
					"agentPath": "/root/\(name)",
				]))
			)
		}
	}

	private func snapshot(thread: String = "subagents-chat") -> ConversationSnapshot
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

	private func controller() -> NSViewController
	{
		let controller = NSViewController()
		controller.view = NSView()
		return controller
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
		for child in view.subviews
		{
			if let button = button(
				label,
				in: child
			)
			{
				return button
			}
		}
		return nil
	}
	private func captureIfRequested(_ tabs: ToolsTabViewController) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_SUBAGENTS_QA_DIR"]
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
		let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
		host.view.cacheDisplay(
			in: host.view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: destination.appendingPathComponent("subagents-tools-tab.png"))
	}
}
