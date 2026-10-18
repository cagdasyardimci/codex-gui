import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabSubagentsIntegrationTests
{
	@Test func workingTimersStopWhenHiddenAndResumeWhenTheirTabReturns() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let presentation = PinnedSummaryPresentation(
			snapshot(),
			ownerIdentity: "timer-fixture"
		)
		let startedAt = Date(timeIntervalSince1970: 1000)
		var currentTime = startedAt
		var ticks: [(timer: Timer, callback: @Sendable (Timer) -> Void)] = []
		defer
		{
			tabs.removeSubagentsTab()
			for tick in ticks
			{
				tick.timer.invalidate()
			}
		}
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
				currentTime
			},
			makeTimeRefreshTimer:
			{
				interval, callback in
				let timer = Timer(
					timeInterval: interval,
					repeats: true,
					block: callback
				)
				ticks.append((timer, callback))
				return timer
			}
		)

		tabs.showSubagents(agents)
		#expect(agents.isRefreshingTimeLabels)
		let elapsed = try #require(elapsedLabel(in: agents.view))
		let row = try #require(elapsed.superview)
		#expect(elapsed.stringValue == "0s")
		try #require(ticks.count == 1)
		let first = ticks[0]
		#expect(first.timer.timeInterval == 1)
		currentTime = startedAt.addingTimeInterval(1)
		first.timer.fire()
		#expect(elapsed.stringValue == "1s")

		tabs.setContentVisible(false)
		#expect(!agents.isRefreshingTimeLabels)
		#expect(!first.timer.isValid)
		currentTime = startedAt.addingTimeInterval(2)
		// Deliver a captured callback even though its timer has already been invalidated.
		first.callback(first.timer)
		#expect(elapsed.stringValue == "1s")
		#expect(!agents.isRefreshingTimeLabels)

		tabs.setContentVisible(true)
		#expect(agents.isRefreshingTimeLabels)
		#expect(elapsed.stringValue == "2s")
		try #require(ticks.count == 2)
		let second = ticks[1]
		currentTime = startedAt.addingTimeInterval(3)
		second.timer.fire()
		#expect(elapsed.stringValue == "3s")
		currentTime = startedAt.addingTimeInterval(4)
		first.callback(first.timer)
		#expect(elapsed.stringValue == "3s")
		#expect(second.timer.isValid)
		#expect(elapsed.superview === row)

		tabs.showSources(controller())
		#expect(!agents.isRefreshingTimeLabels)
		#expect(!second.timer.isValid)
		currentTime = startedAt.addingTimeInterval(5)
		second.callback(second.timer)
		#expect(elapsed.stringValue == "3s")

		tabs.showSubagents(agents)
		#expect(agents.isRefreshingTimeLabels)
		#expect(elapsed.stringValue == "5s")
		try #require(ticks.count == 3)
		let third = ticks[2]
		currentTime = startedAt.addingTimeInterval(6)
		third.timer.fire()
		#expect(elapsed.stringValue == "6s")
		#expect(elapsedLabel(in: agents.view) === elapsed)
		#expect(elapsed.superview === row)

		tabs.removeSubagentsTab()
		#expect(!agents.isRefreshingTimeLabels)
		#expect(agents.parent == nil)
		#expect(!third.timer.isValid)
		currentTime = startedAt.addingTimeInterval(7)
		third.callback(third.timer)
		#expect(elapsed.stringValue == "6s")
		#expect(!agents.isRefreshingTimeLabels)
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
		let fixture = try await CapturedIntentStoreFixture.makeStore(threadID: "subagents-dispatch")
		defer
		{
			fixture.cleanup()
		}
		let store = fixture.store
		await store.inputs.connect()
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
		let tabID = try #require(controller.inspector.toolsTabs.subagentsTabID)
		#expect(controller.inspector.toolsTabs.tabCount == 1)
		controller.inspector.toolsTabs.openNewTab()
		#expect(!controller.inspector.toolsTabs.isSubagentsSelected)
		#expect(controller.inspector.toolsTabs.selectedTabID != tabID)
		let openFromTranscript = try #require(controller.conversation.onOpenSubagents)
		openFromTranscript()
		#expect(controller.inspector.toolsTabs.isSubagentsSelected)
		#expect(controller.inspector.toolsTabs.selectedTabID == tabID)
		#expect(controller.inspector.toolsTabs.subagentsTabID == tabID)
		#expect(controller.inspector.toolsTabs.tabCount == 2)
	}

	private func elapsedLabel(in view: NSView) -> NSTextField?
	{
		if let label = view as? NSTextField,
			label.identifier?.rawValue.hasPrefix("subagent-elapsed:") == true
		{
			return label
		}
		return view.subviews.lazy.compactMap
		{
			elapsedLabel(in: $0)
		}.first
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
		try AppTestPNGWriter.write(
			host.view,
			to: destination.appendingPathComponent("subagents-tools-tab.png")
		)
	}
}
