import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentConversationNavigationIntegrationTests
{
	@Test(arguments: [false, true])
	func panelAndTranscriptOpenChildInTabWhileParentExecutionContinues(
		useTranscript: Bool
	) async throws
	{
		_ = NSApplication.shared
		let project = FileManager.default.temporaryDirectory
			.appendingPathComponent("SubagentNavigation-\(UUID())")
		// Directory preparation is independent of the controller and its main-actor service.
		try await BackgroundTestWork.perform
		{
			try FileManager.default.createDirectory(
				at: project.appendingPathComponent(
					".git",
					isDirectory: true
				),
				withIntermediateDirectories: true
			)
		}
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let defaults = try IsolatedUserDefaultsFixture(prefix: "SubagentNavigation")
		defer
		{
			defaults.cleanup()
		}
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: [
			"id": "child-thread",
			"name": "Child conversation",
			"cwd": project.path,
		])
		let parentTurn = try #require(CodexTurn(json: [
			"id": "history-turn",
			"status": "completed",
			"items": [
				[
					"id": "child-activity",
					"type": "subAgentActivity",
					"kind": "started",
					"agentThreadId": "child-thread",
					"agentPath": "/root/child_agent",
				],
				[
					"id": "missing-activity",
					"type": "subAgentActivity",
					"kind": "completed",
					"agentPath": "/root/missing_agent",
				],
			],
		]))
		service.turnsByThreadID[service.thread.id] = [parentTurn]
		service.turnsByThreadID["child-thread"] = [try #require(CodexTurn(json: [
			"id": "child-turn",
			"status": "completed",
			"items": [[
				"id": "child-response",
				"type": "agentMessage",
				"text": "Child conversation reply",
			]],
		]))]
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaults.defaults)
		)
		defer
		{
			state.shutdown()
		}
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		// Context IO and backend effects publish independently of connection acknowledgement.
		await awaitWorkspaceSnapshot(state.store)
		{
			_ in
			state.selectedProjectURL?.standardizedFileURL == project.standardizedFileURL &&
				state.pendingBackendOperationCount == 0
		}
		#expect(state.selectedProjectURL?.standardizedFileURL == project.standardizedFileURL &&
			state.pendingBackendOperationCount == 0)
		let parentRead = try #require(state.inputs.selectThread(service.thread.id))
		#expect(await parentRead.wait() == .finished)
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canSend
		}
		#expect(state.currentSnapshot.canSend)
		state.inputs.updateDraft("Parent task")
		let submission = try #require(state.inputs.send())
		#expect(await submission.wait() == .finished)
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.updateDraft("Parent follow-up")
		let executionOwner = try #require(state.store.model.execution.owner)
		let controller = MainWindowController(
			store: state.store,
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
		renderSummary(
			controller,
			store: state.store
		)
		let panel = try #require(controller.inspector.conversationSubagents)
		let staleCallback = try #require(panel.onSelectThread)
		let readsBeforeNavigation = service.readThreadIDs.count
		staleCallback("unknown-thread")
		staleCallback("/root/missing_agent")
		#expect(service.readThreadIDs.count == readsBeforeNavigation)
		let missing = try #require(button(
			"Open subagent chat: Missing Agent",
			in: panel.view
		))
		#expect(!missing.isEnabled)

		if useTranscript
		{
			let selectChild = try #require(controller.conversation.onSelectSubagentThread)
			selectChild("child-thread")
		}
		else
		{
			let childButton = try #require(button(
				"Open subagent chat: Child Agent",
				in: panel.view
			))
			try #require(childButton.dispatchConfiguredAction())
		}
		#expect(await waitUntil
		{
			panel.detailController?.state?.entries.contains
			{
				$0.body.contains("Child conversation reply")
			} == true &&
			service.readThreadIDs.count > readsBeforeNavigation &&
			state.pendingBackendOperationCount == 0
		})
		#expect(service.readThreadIDs.last == "child-thread")
		#expect(state.store.model.execution.owner == executionOwner)
		#expect(state.currentSnapshot.activeThreadID == service.thread.id)
		#expect(state.currentSnapshot.selectedThreadID == service.thread.id)
		#expect(controller.inspector.toolsTabs.isSubagentsSelected)
		#expect(panel.parent === controller.inspector.toolsTabs)
		#expect(panel.detailController?.transcript.selectedThreadID == "child-thread")
		#expect(state.currentSnapshot.draft == "Parent follow-up")
		service.turnsByThreadID["child-thread"] = [try #require(CodexTurn(json: [
			"id": "child-turn",
			"status": "completed",
			"items": [[
				"id": "child-response",
				"type": "agentMessage",
				"text": "Child reply updated through the existing subscription",
			]],
		]))]
		service.emit(.agentMessageDelta(
			threadId: "child-thread",
			turnId: "child-turn",
			itemId: "child-response",
			text: "updated"
		))
		#expect(await waitUntil
		{
			panel.detailController?.state?.entries.contains
			{
				$0.body.contains("existing subscription")
			} == true
		})
		if !useTranscript
		{
			try await captureDetailIfRequested(panel)
		}
		service.emit(.agentMessageDelta(
			threadId: service.thread.id,
			turnId: service.nextTurn.id,
			itemId: "parent-response",
			text: "Parent continues"
		))
		#expect(state.store.model.conversations.content[.thread(service.thread.id)]?.entries
			.contains
			{
				$0.body.contains("Parent continues")
			} == true)
		#expect(state.currentSnapshot.draft == "Parent follow-up")
		#expect(state.currentSnapshot.entries.contains
		{
			$0.body.contains("Parent continues")
		})
		#expect(state.store.model.execution.owner == executionOwner)
		renderSummary(
			controller,
			store: state.store
		)
		let backButton = try #require(button(
			"Back to Subagents",
			in: panel.view
		))
		try #require(backButton.dispatchConfiguredAction())
		#expect(panel.selectedAgent == nil)
		#expect(panel.detailController?.view.isHidden == true)
		#expect(controller.inspector.toolsTabs.isSubagentsSelected)
		#expect(state.currentSnapshot.selectedThreadID == service.thread.id)

		let switchRead = try #require(state.inputs.selectThread("unrelated-thread"))
		_ = await switchRead.wait()
		renderSummary(
			controller,
			store: state.store
		)
		let afterSwitchReadCount = service.readThreadIDs.count
		staleCallback("child-thread")
		#expect(service.readThreadIDs.count == afterSwitchReadCount)
		#expect(state.store.model.execution.owner == nil)
		#expect(state.store.model.execution(for: .thread(service.thread.id))
			.owner == executionOwner)
	}

	private func captureDetailIfRequested(_ panel: SubagentsViewController) async throws
	{
		guard let path = ProcessInfo.processInfo.environment["SUBAGENT_DETAIL_SCREENSHOT_PATH"]
		else
		{
			return
		}
		let agent = try #require(panel.selectedAgent)
		let state = try #require(panel.detailController?.state)
		let fixture = SubagentsViewController(
			owner: panel.owner,
			subagents: panel.subagents
		)
		fixture.showConversation(
			agent: agent,
			state: state
		)
		let host = NSViewController()
		host.view = DesktopSurface(AppKitColorTokens.canvas)
		host.addChild(fixture)
		AppKitLayout.pin(
			fixture.view,
			to: host.view,
			inset: 0
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 760,
				height: 800
			),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = host
		window.setContentSize(NSSize(
			width: 760,
			height: 800
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		let detail = try #require(fixture.detailController)
		await detail.transcript.waitForRendering()
		host.view.layoutSubtreeIfNeeded()
		detail.transcript.collectionView.layoutSubtreeIfNeeded()
		host.view.displayIfNeeded()
		#expect(!detail.transcript.displayedRows.isEmpty)
		try AppTestPNGWriter.write(
			host.view,
			to: URL(fileURLWithPath: path)
		)
	}

	private func renderSummary(
		_ controller: MainWindowController,
		store: WorkspaceStateStore
	)
	{
		let snapshot = store.currentSnapshot
		controller.renderPinnedSummary(
			snapshot,
			target: WorkspaceIntentTarget(
				store: store,
				snapshot: snapshot
			)
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

	private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 200
		{
			if condition()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return condition()
	}
}
