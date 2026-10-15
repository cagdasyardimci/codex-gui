import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSubagentNavigationTests
{
	@Test func subagentButtonOpensPanelWithoutExpandingActivity() throws
	{
		_ = NSApplication.shared
		let item = ConversationActivityCollectionItem()
		var openCount = 0
		var toggleCount = 0
		item.configure(
			subagentRow(),
			onToggle:
			{
				toggleCount += 1
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
		let button = try subagentsButton(in: item.view)
		#expect(!button.refusesFirstResponder)
		button.dispatchConfiguredAction()
		#expect(openCount == 1)
		#expect(toggleCount == 0)
		#expect(!buttons(in: item.view).contains
		{
			$0.accessibilityLabel()?.hasPrefix("Expand") == true
		})
	}

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

	@Test func transcriptNavigationRejectsCallbacksAfterOwnerChanges() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		controller.renderedContext = "project:owner"
		controller.requestedContext = "project:owner"
		controller.displayedRows = [.activity(subagentRow())]
		var openCount = 0
		var selected: [String] = []
		controller.onSelectSubagentThread =
		{
			selected.append($0)
		}
		controller.onOpenSubagents =
		{
			openCount += 1
		}
		let item = controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: 0,
				section: 0
			)
		)
		let button = try subagentsButton(in: item.view)
		let child = try #require(buttons(in: item.view).first
		{
			$0.accessibilityLabel()?.hasPrefix("Open conversation:") == true
		})
		child.dispatchConfiguredAction()
		#expect(selected == ["child-thread"])
		button.dispatchConfiguredAction()
		#expect(openCount == 1)

		controller.requestedContext = "project:another-owner"
		button.dispatchConfiguredAction()
		#expect(openCount == 1)

		// Returning to the same owner must not revive a callback from its earlier selection.
		controller.requestedContext = "project:owner"
		controller.selectionGeneration += 1
		child.dispatchConfiguredAction()
		#expect(selected == ["child-thread"])
		button.dispatchConfiguredAction()
		#expect(openCount == 1)
	}

	@Test func groupedAvatarsSelectTheirOwnConversationAndRejectReuse() throws
	{
		_ = NSApplication.shared
		let item = ConversationActivityCollectionItem()
		let agents = ["first", "second", "", "missing"].map
		{
			name in
			var json: [String: Any] = ["kind": "started", "agentPath": "/root/\(name)"]
			if name != "missing"
			{
				json["agentThreadId"] = name
			}
			return CodexSubagentActivity(json: json)
		}
		var selected: [String] = []
		item.configure(
			ConversationSubagentRows.row(
				id: "group",
				agents: agents
			),
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			},
			onOpenSubagents:
			{
			},
			onSelectSubagentThread:
			{
				selected.append($0)
			}
		)
		let childButtons = buttons(in: item.view).filter
		{
			$0.accessibilityLabel()?.hasPrefix("Open conversation:") == true
		}
		#expect(childButtons.count == 4)
		for button in childButtons
		{
			button.dispatchConfiguredAction()
		}
		#expect(selected == ["first", "second"])
		#expect(childButtons.allSatisfy
		{
			!$0.refusesFirstResponder
		})
		#expect(!childButtons[2].isEnabled)
		#expect(!childButtons[3].isEnabled)
		item.prepareForReuse()
		childButtons[0].dispatchConfiguredAction()
		#expect(selected == ["first", "second"])
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

	@Test func childOnlyCallbackWorksAndReconfigurationInvalidatesOldControls() throws
	{
		_ = NSApplication.shared
		let item = ConversationActivityCollectionItem()
		var selected: [String] = []
		func configure()
		{
			item.configure(
				subagentRow(),
				onToggle:
				{
				},
				onOpenFile:
				{
					_ in
				},
				onSelectSubagentThread:
				{
					selected.append($0)
				}
			)
		}
		configure()
		let previous = try #require(buttons(in: item.view).first
		{
			$0.accessibilityLabel()?.hasPrefix("Open conversation:") == true
		})
		previous.dispatchConfiguredAction()
		#expect(selected == ["child-thread"])
		configure()
		previous.dispatchConfiguredAction()
		#expect(selected == ["child-thread"])
		#expect(!buttons(in: item.view).contains
		{
			$0.accessibilityLabel()?.hasPrefix("Open Subagents:") == true
		})
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
