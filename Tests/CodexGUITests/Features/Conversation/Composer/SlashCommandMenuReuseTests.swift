import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	.serialized
)
struct SlashCommandMenuReuseTests
{
	init()
	{
		_ = NSApplication.shared
	}

	@Test func freshAvailabilityAndChoiceCallbacksReplaceRetiredOwnersWithoutRebuildingRows() throws
	{
		let menu = SlashCommandPopoverView()
		var retiredAvailabilityCalls = 0
		var currentAvailabilityCalls = 0
		var retiredChoices = 0
		var currentChoices: [SlashCommandID] = []
		menu.unavailableReason =
		{
			_ in
			retiredAvailabilityCalls += 1
			return nil
		}
		menu.onChoose =
		{
			_ in retiredChoices += 1
		}
		menu.render(prefix: "st")
		let window = host(menu)
		defer
		{
			window.close()
		}
		let table = try self.table(in: menu)
		let cell = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		let retiredCalls = retiredAvailabilityCalls
		menu.unavailableReason =
		{
			_ in
			currentAvailabilityCalls += 1
			return nil
		}
		menu.onChoose =
		{
			currentChoices.append($0.id)
		}
		menu.render(prefix: "sta")
		#expect(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		) === cell)
		#expect(retiredAvailabilityCalls == retiredCalls)
		#expect(currentAvailabilityCalls == 1)
		#expect(table.sendAction(
			table.action,
			to: table.target
		))
		#expect(retiredChoices == 0)
		#expect(currentChoices == [.status])
	}

	@Test func changedAvailabilityIncludingCanonicalUnicodeRefreshesVisibleRows() throws
	{
		let menu = SlashCommandPopoverView()
		var reason: String?
		menu.unavailableReason =
		{
			_ in reason
		}
		menu.render(prefix: "sta")
		let window = host(menu)
		defer
		{
			window.close()
		}
		let table = try self.table(in: menu)
		let available = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		reason = "Wait for café."
		menu.render(prefix: "sta")
		let unavailable = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		#expect(unavailable !== available)
		#expect(unavailable.toolTip?.utf8.elementsEqual("Wait for café.".utf8) == true)
		#expect(title(in: unavailable)?.textColor == .secondaryLabelColor)
		reason = "Wait for cafe\u{0301}."
		menu.render(prefix: "sta")
		let exact = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		#expect(exact !== unavailable)
		#expect(exact.toolTip?.utf8.elementsEqual("Wait for cafe\u{0301}.".utf8) == true)
		#expect(exact.accessibilityLabel()?.utf8.elementsEqual(
			"/status. Show conversation and context status. Wait for cafe\u{0301}.".utf8
		) == true)
		reason = nil
		menu.render(prefix: "sta")
		let restored = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		#expect(title(in: restored)?.textColor == .labelColor)
	}

	@Test func exactSkillTextAndPathsRefreshWhileRemovalClearsTheSelection() throws
	{
		let menu = SlashCommandPopoverView()
		let original = try skill(text: "café")
		let replacement = try skill(text: "cafe\u{0301}")
		#expect(original == replacement)
		menu.availableSkills = [original]
		menu.render(prefix: "caf")
		let window = host(menu)
		defer
		{
			window.close()
		}
		let table = try self.table(in: menu)
		let first = try #require(table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		))
		menu.availableSkills = [replacement]
		menu.render(prefix: "caf")
		let second = try #require(table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		))
		#expect(second !== first)
		#expect(title(in: second)?.stringValue.utf8.elementsEqual("cafe\u{0301}".utf8) == true)
		#expect(second.toolTip?.utf8.elementsEqual("Description cafe\u{0301}".utf8) == true)
		#expect(menu.selectedSkill?.path.utf8.elementsEqual("/skills/cafe\u{0301}".utf8) == true)
		#expect(!menu.tableView(
			table,
			shouldSelectRow: 0
		))
		menu.availableSkills = []
		menu.render(prefix: "caf")
		#expect(table.numberOfRows == 0)
		#expect(menu.selectedSkill == nil)
		#expect(table.selectedRow == -1)
	}

	nonisolated private static func postLocaleNotificationFromWorker(
		_ notifications: NotificationCenter
	) -> Bool
	{
		notifications.post(
			name: NSLocale.currentLocaleDidChangeNotification,
			object: nil
		)
		return Thread.isMainThread
	}

	@Test func skippedMenuWorkStillRefreshesComposerTokenRangeAndRetiredDraftGeneration() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		controller.render(snapshot(draft: "/sta 🧭 first"))
		controller.composer.setSelectedRange(NSRange(
			location: 4,
			length: 0
		))
		controller.updateComposerCompletion()
		let menu = controller.slashCommandController
		let window = host(menu)
		defer
		{
			window.close()
		}
		let table = try self.table(in: menu)
		let cell = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		let replacementText = "  /sta 🧭 second"
		controller.composer.string = replacementText
		controller.composer.setSelectedRange(NSRange(
			location: 6,
			length: 0
		))
		controller.updateComposerCompletion()
		#expect(controller.slashCompletionRange == NSRange(
			location: 2,
			length: 4
		))
		#expect(controller.slashCompletionText?.utf8.elementsEqual(replacementText.utf8) == true)
		#expect(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		) === cell)
		let previousGeneration = controller.selectionGeneration
		var replacement = snapshot(draft: replacementText)
		replacement.composerDraftLifetime = 1
		controller.render(replacement)
		#expect(controller.selectionGeneration != previousGeneration)
		var choices = 0
		controller.onSlashCommand =
		{
			_ in choices += 1
		}
		let status = SlashCommandRegistry.descriptor(for: .status)
		controller.chooseSlashCommand(
			status,
			execute: true
		)
		#expect(choices == 0)
		controller.composer.setSelectedRange(NSRange(
			location: 6,
			length: 0
		))
		controller.updateComposerCompletion()
		#expect(controller.slashCompletionGeneration == controller.selectionGeneration)
		#expect(controller.slashCompletionRange == NSRange(
			location: 2,
			length: 4
		))
		#expect(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		) === cell)
		controller.chooseSlashCommand(
			status,
			execute: false
		)
		#expect(controller.composer.string.utf8.elementsEqual("  /status 🧭 second".utf8))
		#expect(choices == 0)
	}

	private func host(_ menu: SlashCommandPopoverView) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 720,
				height: 316
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = menu
		window.layoutIfNeeded()
		menu.view.layoutSubtreeIfNeeded()
		return window
	}

	private func table(in menu: SlashCommandPopoverView) throws -> SlashCommandMenuTableView
	{
		let scroll = try #require(menu.view.subviews.first?.subviews.first as? NSScrollView)
		return try #require(scroll.documentView as? SlashCommandMenuTableView)
	}

	private func title(in cell: NSView) -> NSTextField?
	{
		if let content = cell as? DesktopSearchResultContentView
		{
			return content.primaryLabel
		}
		return cell.subviews.lazy.compactMap
		{
			title(in: $0)
		}.first
	}

	private func skill(text: String) throws -> AvailableSkill
	{
		try #require(AvailableSkill(json: [
			"name": text,
			"description": "Description \(text)",
			"path": "/skills/\(text)",
			"scope": "user",
			"enabled": true,
			"interface": ["displayName": text],
		]))
	}

	private func snapshot(draft: String) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: nil,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: draft,
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
