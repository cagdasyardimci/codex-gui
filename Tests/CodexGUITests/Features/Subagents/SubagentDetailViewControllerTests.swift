import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentDetailViewControllerTests
{
	@Test func backPreservesExpandedListAndItsScrollDocument() throws
	{
		_ = NSApplication.shared
		let controller = makeController()
		let more = try button(
			in: controller.view,
			title: "Show 2 more"
		)
		more.performClick(nil)
		let scroll = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSScrollView
		}.first)
		let document = try #require(scroll.documentView)
		let origin = scroll.contentView.bounds.origin
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
		back.performClick(nil)
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
