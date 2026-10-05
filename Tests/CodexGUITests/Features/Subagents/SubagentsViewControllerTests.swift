import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SubagentsViewControllerTests
{
	@Test func donePreviewExpandsAndPreservesExpansionAcrossUpdates() throws
	{
		_ = NSApplication.shared
		let controller = makeController(count: 12)
		#expect(labels(controller.view).contains("Active · 0"))
		#expect(labels(controller.view).contains("No active subagents"))
		#expect(agentRows(controller.view).count == 10)
		let more = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue == "subagents-show-more"
		})
		#expect(more.title == "Show 2 more")
		more.performClick(nil)
		#expect(agentRows(controller.view).count == 12)
		controller.update(projection(count: 13))
		#expect(agentRows(controller.view).count == 13)
		#expect(labels(controller.view).contains("Done · 13"))
		try captureIfRequested(controller)
	}

	@Test func lifecycleUpdateMovesRowsAndRetainsExceptionalOutcomeLabels()
	{
		_ = NSApplication.shared
		let controller = makeController(count: 0)
		controller.update(ConversationSubagents(entries: [
			entry(
				index: 0,
				kind: "started"
			),
			entry(
				index: 1,
				kind: "failed"
			),
			entry(
				index: 2,
				kind: "interrupted"
			),
		]))
		#expect(agentRows(controller.view).count == 3)
		#expect(labels(controller.view).contains("Active · 1"))
		#expect(labels(controller.view).contains("Done · 2"))
		#expect(labels(controller.view).contains("Failed"))
		#expect(labels(controller.view).contains("Interrupted"))
		controller.update(ConversationSubagents(entries: [entry(
			index: 0,
			kind: "completed"
		)]))
		#expect(agentRows(controller.view).count == 1)
		#expect(labels(controller.view).contains("No active subagents"))
	}

	@Test func agentButtonsNavigateToIndividualThreadAndRespondToCallbackChanges() throws
	{
		_ = NSApplication.shared
		let controller = makeController(count: 2)
		let buttons = agentButtons(controller.view)
		#expect(buttons.allSatisfy
		{
			!$0.isEnabled
		})
		var selected: [String] = []
		controller.onSelectThread =
		{
			selected.append($0)
		}
		#expect(buttons.allSatisfy
		{
			$0.isEnabled
		})
		buttons[1].performClick(nil)
		buttons[0].performClick(nil)
		#expect(selected == ["agent-1", "agent-0"])
		controller.onSelectThread = nil
		#expect(buttons.allSatisfy
		{
			!$0.isEnabled
		})
		try sendAction(buttons[0])
		#expect(selected == ["agent-1", "agent-0"])
	}

	@Test func missingEmptyOrWhitespaceThreadIdentityCannotNavigate() throws
	{
		_ = NSApplication.shared
		let controller = makeController(count: 0)
		let invalidIDs: [String?] = [nil, "", " \n\t"]
		let entries = invalidIDs.enumerated().map
		{
			index, threadID in
			ConversationEntry(
				id: "invalid-\(index)",
				kind: .tool,
				title: "Subagent",
				body: "",
				activity: .subagent(CodexSubagentActivity(
					kind: "started",
					threadID: threadID,
					path: "/root/invalid_\(index)"
				))
			)
		}
		controller.update(ConversationSubagents(entries: entries))
		var selected: [String] = []
		controller.onSelectThread =
		{
			selected.append($0)
		}
		let buttons = agentButtons(controller.view)
		#expect(buttons.count == 3)
		#expect(buttons.allSatisfy
		{
			!$0.isEnabled
		})
		for button in buttons
		{
			try sendAction(button)
		}
		#expect(selected.isEmpty)
	}

	@Test func removedAndRebuiltButtonsCannotNavigateUsingRetainedReferences() throws
	{
		_ = NSApplication.shared
		let controller = makeController(count: 2)
		var selected: [String] = []
		controller.onSelectThread =
		{
			selected.append($0)
		}
		let oldButtons = agentButtons(controller.view)
		controller.update(projection(count: 1))
		try sendAction(oldButtons[0])
		try sendAction(oldButtons[1])
		#expect(selected.isEmpty)
		let currentButton = try #require(agentButtons(controller.view).first)
		currentButton.performClick(nil)
		#expect(selected == ["agent-0"])
	}

	@Test func completionTimesRefreshWithoutRebuildingRowsAndFollowVisibility() throws
	{
		_ = NSApplication.shared
		var currentTime = Date(timeIntervalSince1970: 10000)
		let controller = makeController(
			count: 0,
			now:
			{
				currentTime
			}
		)
		let agent = CodexSubagentActivity(
			kind: "completed",
			threadID: "finished",
			path: "/root/finished",
			completedAt: currentTime.addingTimeInterval(-240)
		)
		controller.update(ConversationSubagents(entries: [ConversationEntry(
			id: "finished-event",
			kind: .tool,
			title: "Subagent",
			body: "",
			activity: .subagent(agent)
		)]))
		let row = try #require(agentRows(controller.view).first)
		let label = try #require(descendants(row).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.identifier?.rawValue.hasPrefix("subagent-completed:") == true
		})
		#expect(label.stringValue == "4m ago")
		#expect(label.alignment == .right)
		#expect(label.font?.pointSize == 12)
		currentTime = currentTime.addingTimeInterval(60)
		controller.refreshTimeLabels()
		#expect(label.stringValue == "5m ago")
		#expect(agentRows(controller.view).first === row)
		controller.viewDidAppear()
		#expect(controller.isRefreshingTimeLabels)
		controller.showConversation(
			agent: agent,
			state: SubagentConversationState(agent: agent)
		)
		#expect(!controller.isRefreshingTimeLabels)
		controller.showList()
		#expect(controller.isRefreshingTimeLabels)
		controller.viewDidDisappear()
		#expect(!controller.isRefreshingTimeLabels)
	}

	@Test func missingCompletionTimesRemainAbsentAndExceptionalStatusesRemainVisible()
	{
		_ = NSApplication.shared
		let controller = makeController(count: 0)
		controller.update(ConversationSubagents(entries: [entry(
			index: 0,
			kind: "failed"
		)]))
		#expect(labels(controller.view).contains("Failed"))
		#expect(!descendants(controller.view).contains
		{
			$0.identifier?.rawValue.hasPrefix("subagent-completed:") == true
		})
		controller.viewDidAppear()
		#expect(!controller.isRefreshingTimeLabels)
		controller.viewDidDisappear()
	}

	@Test func workingElapsedTimeTicksInPlaceAndResumesAfterTabVisibilityChanges() throws
	{
		_ = NSApplication.shared
		var currentTime = Date(timeIntervalSince1970: 10000)
		let controller = makeController(
			count: 0,
			now:
			{
				currentTime
			}
		)
		let agent = CodexSubagentActivity(
			kind: "started",
			threadID: "working",
			path: "/root/working",
			startedAt: currentTime.addingTimeInterval(-4227)
		)
		controller.update(ConversationSubagents(entries: [ConversationEntry(
			id: "working-event",
			kind: .tool,
			title: "Subagent",
			body: "",
			activity: .subagent(agent)
		)]))
		let row = try #require(agentRows(controller.view).first as? NSStackView)
		#expect(row.alignment == .top)
		#expect(labels(row).contains("Working"))
		#expect(labels(row).contains("1h 10m 27s"))
		let previousButton = try #require(agentButtons(row).first)
		controller.setPresentationVisible(true)
		#expect(controller.isRefreshingTimeLabels)
		controller.setPresentationVisible(false)
		#expect(!controller.isRefreshingTimeLabels)
		currentTime = currentTime.addingTimeInterval(1)
		controller.setPresentationVisible(true)
		#expect(labels(row).contains("1h 10m 28s"))
		#expect(agentButtons(row).first === previousButton)
		controller.setPresentationVisible(false)
	}

	private func agentButtons(_ view: NSView) -> [NSButton]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.filter
		{
			$0.identifier?.rawValue.hasPrefix("subagent-open:") == true
		}
	}

	private func sendAction(_ button: NSButton) throws
	{
		let action = try #require(button.action)
		NSApplication.shared.sendAction(
			action,
			to: button.target,
			from: button
		)
	}

	private func makeController(
		count: Int,
		now: @escaping () -> Date = Date.init
	) -> SubagentsViewController
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/sample/workspace"
		))
		let snapshot = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		return SubagentsViewController(
			owner: FeaturePresentationOwner(snapshot),
			subagents: projection(count: count),
			now: now
		)
	}

	private func projection(count: Int) -> ConversationSubagents
	{
		ConversationSubagents(entries: (0 ..< count).map
		{
			entry(
				index: $0,
				kind: "completed"
			)
		})
	}

	private func entry(
		index: Int,
		kind: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: "event-\(index)",
			kind: .tool,
			title: "Subagent",
			body: "",
			activity: .subagent(CodexSubagentActivity(
				kind: kind,
				threadID: "agent-\(index)",
				path: "/root/implementation_\(index)"
			))
		)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private func labels(_ view: NSView) -> [String]
	{
		descendants(view).compactMap
		{
			($0 as? NSTextField)?.stringValue
		}
	}

	private func agentRows(_ view: NSView) -> [NSView]
	{
		descendants(view).filter
		{
			$0.identifier?.rawValue.hasPrefix("subagent:") == true
		}
	}

	private func captureIfRequested(_ controller: SubagentsViewController) throws
	{
		let fixturePaths = [
			("SUBAGENTS_SCREENSHOT_PATH", false),
			("SUBAGENTS_ACTIVE_SCREENSHOT_PATH", true),
		]
		for (variable, showsActiveAgents) in fixturePaths
		{
			if let path = ProcessInfo.processInfo.environment[variable]
			{
				try captureFixture(
					controller,
					path: path,
					showsActiveAgents: showsActiveAgents
				)
			}
		}
	}

	private func captureFixture(
		_ controller: SubagentsViewController,
		path: String,
		showsActiveAgents: Bool
	) throws
	{
		let agents = ["subagent_feature", "tab_integration", "transcript_navigation"]
		let fixtureNow = Date(timeIntervalSince1970: 10000)
		let elapsedMinutes = [4, 26, 29]
		let entries = agents.enumerated().map
		{
			index, name in
			let isActive = showsActiveAgents && index < 2
			return ConversationEntry(
				id: "fixture-\(index)",
				kind: .tool,
				title: "Subagent",
				body: "",
				activity: .subagent(CodexSubagentActivity(
					kind: isActive ? "started" : "completed",
					path: "/root/\(name)",
					completedAt: isActive ? nil
						: fixtureNow.addingTimeInterval(-Double(elapsedMinutes[index]) * 60),
					startedAt: isActive ? fixtureNow.addingTimeInterval(-Double(4227 + index)) : nil
				))
			)
		}
		// Missing thread IDs exercise disabled controls without changing their legibility.
		let fixture = SubagentsViewController(
			owner: controller.owner,
			subagents: ConversationSubagents(entries: entries),
			now:
			{
				fixtureNow
			}
		)
		let host = NSViewController()
		host.view = DesktopSurface(DesktopTheme.canvas)
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
				width: 640,
				height: 800
			),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = host
		window.setContentSize(NSSize(
			width: 640,
			height: 800
		))
		defer
		{
			window.close()
		}
		host.view.layoutSubtreeIfNeeded()
		let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
		host.view.cacheDisplay(
			in: host.view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: URL(fileURLWithPath: path))
	}
}
