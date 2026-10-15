import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentDetailViewControllerTests
{
	@Test func detailEmbedsOnlyTheSharedTranscriptAndKeepsComposerOut() async throws
	{
		_ = NSApplication.shared
		let controller = makeController()
		let agent = try #require(controller.subagents.agents.first)
		let reply = ConversationEntry(
			id: "child:reply",
			kind: .agent,
			title: "Codex",
			body: "Child reply"
		)
		controller.showConversation(
			agent: agent,
			state: SubagentConversationState(
				agent: agent,
				entries: [reply]
			)
		)
		let detail = try #require(controller.detailController)
		_ = detail.view
		await detail.transcript.waitForRendering()
		#expect(detail.children.count == 1)
		#expect(detail.children.first === detail.transcript)
		#expect(detail.transcript.entries == [reply])
		#expect(!descendants(detail.view).contains
		{
			$0 is ContextComposerTextView
		})
	}

	@Test func backPreservesExpandedListAndItsScrollDocument() throws
	{
		_ = NSApplication.shared
		let controller = makeController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 420,
				height: 240
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.close()
		}
		let more = try button(
			in: controller.view,
			title: "Show 2 more"
		)
		try #require(more.dispatchConfiguredAction())
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let scroll = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSScrollView
		}.first)
		let document = try #require(scroll.documentView)
		try #require(document.frame.height > scroll.contentView.bounds.height + 120)
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: 120
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		let origin = scroll.contentView.bounds.origin
		try #require(origin.y > 0)
		let agent = try #require(controller.subagents.agents.first)
		var backCount = 0
		controller.onBack =
		{
			backCount += 1
		}
		controller.showConversation(
			agent: agent,
			state: SubagentConversationState(agent: agent)
		)
		#expect(scroll.isHidden)
		let detail = try #require(controller.detailController)
		let back = try #require(descendants(detail.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "Back to Subagents"
		})
		try #require(back.dispatchConfiguredAction())
		controller.view.layoutSubtreeIfNeeded()
		#expect(backCount == 1)
		#expect(controller.selectedAgent == nil)
		#expect(!scroll.isHidden)
		#expect(scroll.documentView === document)
		#expect(scroll.contentView.bounds.origin == origin)
		let rows = descendants(document).filter
		{
			$0.identifier?.rawValue.hasPrefix("subagent:") == true
		}
		#expect(rows.count == 12)
		#expect(!descendants(document).contains
		{
			$0.identifier?.rawValue == "subagents-show-more"
		})
	}

	@Test func replacedDetailCannotRetryOrNavigateBack() throws
	{
		_ = NSApplication.shared
		let controller = makeController()
		let first = controller.subagents.agents[0]
		let second = controller.subagents.agents[1]
		var retryCount = 0
		var backCount = 0
		controller.onRetry =
		{
			retryCount += 1
		}
		controller.onBack =
		{
			backCount += 1
		}
		controller.showConversation(
			agent: first,
			state: SubagentConversationState(
				agent: first,
				error: "Load failed"
			)
		)
		let previous = try #require(controller.detailController)
		let previousRetry = try button(
			in: previous.view,
			title: "Retry"
		)
		controller.showConversation(
			agent: second,
			state: SubagentConversationState(
				agent: second,
				error: "Load failed"
			)
		)
		previousRetry.performClick(nil)
		previous.onBack?()
		#expect(retryCount == 0)
		#expect(backCount == 0)
		#expect(controller.selectedAgent == second)
		let current = try #require(controller.detailController)
		try button(
			in: current.view,
			title: "Retry"
		).performClick(nil)
		#expect(retryCount == 1)
		current.onBack?()
		#expect(backCount == 1)
	}

	private func makeController() -> SubagentsViewController
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/sample/workspace"
		))
		let snapshot = WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
		let entries = (0 ..< 12).map
		{
			index in
			ConversationEntry(
				id: "event-\(index)",
				kind: .tool,
				title: "Subagent",
				body: "",
				activity: .subagent(CodexSubagentActivity(
					kind: "completed",
					threadID: "child-\(index)",
					path: "/root/agent_\(index)"
				))
			)
		}
		return SubagentsViewController(
			owner: FeaturePresentationOwner(snapshot),
			subagents: ConversationSubagents(entries: entries)
		)
	}

	private func button(
		in view: NSView,
		title: String
	) throws -> NSButton
	{
		try #require(descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == title
		})
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
