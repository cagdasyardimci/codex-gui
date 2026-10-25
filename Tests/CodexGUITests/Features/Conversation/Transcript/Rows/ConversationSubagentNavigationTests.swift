import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSubagentNavigationTests
{

	@Test func reusedActivityItemClearsSubagentNavigation() throws
	{
		_ = NSApplication.shared
		let item = ConversationActivityCollectionItem()
		var openCount = 0
		item.configure(
			subagentRow(),
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			},
			onOpenSubagents:
			{
				openCount += 1
			}
		)
		let previousButton = try subagentsButton(in: item.view)
		item.prepareForReuse()
		previousButton.dispatchConfiguredAction()
		#expect(openCount == 0)
	}

	@Test func overflowMenuSelectsEachChildAndDisablesMissingIDs() throws
	{
		_ = NSApplication.shared
		for count in [5, 8]
		{
			let agents = (0 ..< count).map
			{
				index in
				CodexSubagentActivity(json: [
					"kind": "completed",
					"agentThreadId": index == 6 ? " " : "child-\(index)",
					"agentPath": "/root/agent_\(index)"
				])
			}
			var selected: [String] = []
			let avatars = ConversationSubagentAvatars.make(
				agents,
				onSelectThread:
				{
					selected.append($0)
				}
			)
			let overflow = try #require(buttons(in: avatars).first
			{
				$0.accessibilityLabel() == "More subagent conversations"
			})
			let menu = try #require(overflow.menu)
			#expect(menu.items.count == count - 4)
			for (offset, item) in menu.items.enumerated()
			{
				#expect(item.isEnabled == (offset + 4 != 6))
				let action = try #require(item.action)
				_ = NSApplication.shared.sendAction(
					action,
					to: item.target,
					from: item
				)
			}
			let expected = (4 ..< count).filter
			{
				$0 != 6
			}.map
			{
				"child-\($0)"
			}
			#expect(selected == expected)
		}
	}

	private func subagentRow() -> ConversationActivityRow
	{
		ConversationSubagentRows.row(
			id: "turn:subagent",
			agents: [CodexSubagentActivity(json: [
				"kind": "started",
				"agentThreadId": "child-thread",
				"agentPath": "/root/app_client"
			])]
		)
	}

	private func subagentsButton(in view: NSView) throws -> NSButton
	{
		try #require(buttons(in: view).first
		{
			$0.accessibilityLabel()?.hasPrefix("Open Subagents:") == true
		})
	}

	private func buttons(in view: NSView) -> [NSButton]
	{
		let ownButton = (view as? NSButton).map
		{
			[$0]
		} ?? []
		return ownButton + view.subviews.flatMap
		{
			buttons(in: $0)
		}
	}
}
