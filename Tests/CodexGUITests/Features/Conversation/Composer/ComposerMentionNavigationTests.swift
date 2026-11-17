import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerMentionNavigationTests
{
	@Test(
		.appKitIsolation,
		arguments: ["work", "plugins"]
	)
	func navigationConsumesOnlyTheMentionAndNeverSends(query: String) throws
	{
		try exercise(
			query: query,
			replacesOwner: false
		)
	}

	@Test(
		.appKitIsolation,
		arguments: ["work", "plugins"]
	)
	func navigationRejectsAReplacedDraftOwner(query: String) throws
	{
		try exercise(
			query: query,
			replacesOwner: true
		)
	}

	@Test(.appKitIsolation)
	func disabledGoalAndUnavailablePlanCannotBeChosenAndKeyboardSkipsBoth() throws
	{
		let menu = ComposerMentionMenu()
		menu.render(
			query: "",
			skills: [],
			paths: [],
			planMode: false,
			allowsPlanMode: false,
			allowsProjectSelection: true,
			allowsPluginManagement: true
		)
		let scroll = try #require(menu.view.subviews.first as? NSScrollView)
		let table = try #require(scroll.documentView as? NSTableView)
		func title(_ row: Int) -> String?
		{
			let cell = menu.tableView(
				table,
				viewFor: nil,
				row: row
			)
			return cell?.subviews.compactMap
			{
				$0 as? DesktopSearchResultContentView
			}.first?
			.primaryLabel.stringValue
		}
		let goal = try #require((0 ..< table.numberOfRows).first
		{
			title($0) == "Goal"
		})
		let plan = try #require((0 ..< table.numberOfRows).first
		{
			title($0) == "Plan mode"
		})
		let project = try #require((0 ..< table.numberOfRows)
			.first
			{
				title($0) == "Work in a project"
			})
		let plugins = try #require((0 ..< table.numberOfRows)
			.first
			{
				title($0) == "Manage plugins"
			})
		var choices = 0
		menu.onChoose =
		{
			_ in choices += 1
		}
		for row in [goal, plan]
		{
			#expect(!menu.tableView(
				table,
				shouldSelectRow: row
			))
			table.selectRowIndexes(
				IndexSet(integer: row),
				byExtendingSelection: false
			)
			menu.chooseSelected()
			#expect(table.sendAction(
				try #require(table.action),
				to: table.target
			))
		}
		#expect(choices == 0)
		table.selectRowIndexes(
			IndexSet(integer: project),
			byExtendingSelection: false
		)
		menu.moveSelection(by: 1)
		#expect(table.selectedRow == plugins)
		menu.moveSelection(by: -1)
		#expect(table.selectedRow == project)
		#expect(table.sendAction(
			try #require(table.action),
			to: table.target
		))
		#expect(choices == 1)
		menu.render(
			query: "Goal",
			skills: [],
			paths: [],
			planMode: false,
			allowsPlanMode: false,
			allowsProjectSelection: true,
			allowsPluginManagement: true
		)
		#expect(table.selectedRow == -1)
		menu.chooseSelected()
		#expect(table.sendAction(
			try #require(table.action),
			to: table.target
		))
		#expect(choices == 1)
	}

	@Test(
		.appKitIsolation,
		arguments: [true, false]
	)
	func planUsesSlashAvailabilityAndPreservesTheRemainingDraft(available: Bool) throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(contentViewController: controller)
		window.prepareForTesting()
		defer
		{
			controller.mentionPopover?.close(); window.close()
		}
		let text = "Keep 🧭 @plan and the rest"
		controller.composer.string = text
		let token = (text as NSString).range(of: "@plan")
		controller.composer.setSelectedRange(NSRange(
			location: NSMaxRange(token),
			length: 0
		))
		var commands: [SlashCommandID] = []
		var sends = 0
		controller.onSlashCommand =
		{
			commands.append($0.id)
		}
		controller.onSend =
		{
			sends += 1
		}
		controller.slashCommandController
			.unavailableReason =
			{
				_ in available ? nil : "Unavailable"
			}
		try #require(window.makeFirstResponder(controller.composer))
		controller.updateComposerCompletion()
		window.makeFirstResponder(nil)
		controller.mentionMenu.chooseSelected()
		#expect(commands == (available ? [.plan] : []))
		#expect(sends == 0)
		#expect(controller.composer.draftText == (available ? "Keep 🧭  and the rest" : text))
		if available
		{
			#expect(window.firstResponder === controller.composer)
		}
	}

	@Test(
		.appKitIsolation,
		arguments: [false, true]
	)
	func plusMenuPreservesSelectedDraftAndRejectsReplacedOwner(replacesOwner: Bool) throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(contentViewController: controller)
		window.prepareForTesting()
		defer
		{
			controller.mentionPopover?.close()
			window.close()
		}
		window.setContentSize(NSSize(
			width: 900,
			height: 700
		))
		window.contentView?.layoutSubtreeIfNeeded()
		window.orderFront(nil)
		let draft = "Keep 🧭 selected text and attachments"
		let selection = (draft as NSString).range(of: "selected text")
		controller.composer.string = draft
		controller.composer.setSelectedRange(selection)
		var projects = 0
		var draftChanges = 0
		var sends = 0
		controller.onChooseProject =
		{
			projects += 1
		}
		controller.onDraftChange =
		{
			_ in draftChanges += 1
		}
		controller.onSend =
		{
			sends += 1
		}
		#expect(controller.addContextButton.sendAction(
			try #require(controller.addContextButton.action),
			to: controller.addContextButton.target
		))
		#expect(controller.mentionPopover?.isShown == true)
		#expect(controller.composer.string == draft)
		#expect(controller.composer.selectedRange() == selection)
		let menu = controller.mentionMenu
		let scroll = try #require(menu.view.subviews.first as? NSScrollView)
		let table = try #require(scroll.documentView as? NSTableView)
		let project = try #require((0 ..< table.numberOfRows).first
		{
			row in
			menu.tableView(
				table,
				viewFor: nil,
				row: row
			)?.subviews
				.compactMap
				{
					$0 as? DesktopSearchResultContentView
				}
				.first?.primaryLabel.stringValue == "Work in a project"
		})
		table.selectRowIndexes(
			IndexSet(integer: project),
			byExtendingSelection: false
		)
		if replacesOwner
		{
			controller.selectionGeneration += 1
		}
		menu.chooseSelected()
		#expect(projects == (replacesOwner ? 0 : 1))
		#expect(draftChanges == 0)
		#expect(sends == 0)
		#expect(controller.composer.string == draft)
		#expect(controller.composer.selectedRange() == selection)
		#expect(controller.mentionPopover?.isShown == false)
	}

	private func exercise(
		query: String,
		replacesOwner: Bool
	) throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(contentViewController: controller)
		window.prepareForTesting()
		defer
		{
			controller.mentionPopover?.close()
			window.close()
		}
		let draft = "Keep 🧭 @\(query) and the rest"
		let token = (draft as NSString).range(of: "@\(query)")
		controller.composer.string = draft
		controller.composer.setSelectedRange(NSRange(
			location: NSMaxRange(token),
			length: 0
		))
		var destinations: [String] = []
		var sends = 0
		controller.onChooseProject =
		{
			destinations.append("work")
		}
		controller.onManagePlugins =
		{
			destinations.append("plugins")
		}
		controller.onSend =
		{
			sends += 1
		}
		try #require(window.makeFirstResponder(controller.composer))
		controller.updateComposerCompletion()
		if replacesOwner
		{
			controller.selectionGeneration += 1
		}
		controller.mentionMenu.chooseSelected()
		#expect(sends == 0)
		#expect(destinations == (replacesOwner ? [] : [query]))
		#expect(controller.composer.draftText == (replacesOwner ? draft : "Keep 🧭  and the rest"))
	}
}
