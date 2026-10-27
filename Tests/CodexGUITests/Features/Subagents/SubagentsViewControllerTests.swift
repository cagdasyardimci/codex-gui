import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SubagentsViewControllerTests
{
	@Test func emptyListOmitsStatusCopy()
	{
		_ = NSApplication.shared
		let controller = makeController(count: 0)
		let visibleLabels = labels(controller.view)
		#expect(visibleLabels.contains("Active · 0"))
		#expect(visibleLabels.contains("Finished · 0"))
		#expect(!visibleLabels.contains("No active subagents"))
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
				width: 640,
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
