import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Native composer slash completion",
	.serialized
)
struct ComposerSlashCommandTests
{
	@Test func arrowsChooseCommandTabInsertsWithoutExecutingAndEscapePreservesText()
	{
		let controller = makeController(text: "/")
		var executions: [SlashCommandInvocation] = []
		controller.onSlashCommand =
		{
			executions.append($0)
		}
		#expect(controller.slashCommandController.selectedCommand?.id == .new)
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.moveDown(_:))))
		#expect(controller.slashCommandController.selectedCommand?.id == .resume)
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.insertTab(_:))))
		#expect(controller.composer.string == "/resume ")
		#expect(executions.isEmpty)
		#expect(controller.slashCompletionRange == nil)
		controller.composer.string = "/sta"
		controller.composer.setSelectedRange(NSRange(
			location: 4,
			length: 0
		))
		controller.updateComposerCompletion()
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.cancelOperation(_:))))
		#expect(controller.composer.string == "/sta")
		#expect(executions.isEmpty)
	}

	@Test func returnDispatchesCanonicalCommandAndPreservesUTF16Prompt()
	{
		let controller = makeController(text: "/pla 🧭 inspect café")
		controller.composer.setSelectedRange(NSRange(
			location: 4,
			length: 0
		))
		controller.updateComposerCompletion()
		var drafts: [String] = []
		var executions: [SlashCommandInvocation] = []
		controller.onDraftChange =
		{
			drafts.append($0)
		}
		controller.onSlashCommand =
		{
			executions.append($0)
		}
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.insertNewline(_:))))
		#expect(controller.composer.string == "/plan 🧭 inspect café")
		#expect(drafts.last == controller.composer.string)
		#expect(executions.last?.id == .plan)
		#expect(executions.last?.arguments == "🧭 inspect café")
		#expect(controller.slashCompletionRange == nil)
	}

	@Test func slashListPrecedesAtCompletionAndUnknownReturnUsesRuntimeSend()
	{
		let controller = makeController(text: "/st")
		controller.fileSearchWasCompletion = true
		controller.completionRange = NSRange(
			location: 0,
			length: 3
		)
		controller.updateComposerCompletion()
		#expect(controller.completionRange == nil)
		#expect(controller.slashCommandController.commands.map(\.id) == [.status])
		controller.composer.string = "/unknown"
		controller.composer.setSelectedRange(NSRange(
			location: 8,
			length: 0
		))
		controller.updateComposerCompletion()
		var sends = 0
		controller.onSend =
		{
			sends += 1
		}
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.insertNewline(_:))))
		#expect(sends == 1)
		#expect(controller.composer.string == "/unknown")
	}

	@Test func markedTextKeepsIMEKeyHandlingAndOwnerChangeDismissesCompletion()
	{
		let controller = makeController(text: "/sta")
		controller.composer.setMarkedText(
			"t",
			selectedRange: NSRange(
				location: 1,
				length: 0
			),
			replacementRange: NSRange(
				location: 4,
				length: 0
			)
		)
		controller.updateComposerCompletion()
		#expect(controller.composer.hasMarkedText())
		#expect(!controller.handleSlashCommandKey(#selector(NSResponder.insertNewline(_:))))
		#expect(controller.slashCompletionRange == nil)
		controller.composer.unmarkText()
		controller.composer.string = "/sta"
		controller.composer.setSelectedRange(NSRange(
			location: 4,
			length: 0
		))
		controller.updateComposerCompletion()
		var next = snapshot(draft: "/sta")
		next.composerDraftLifetime = 1
		controller.render(next)
		#expect(controller.slashCompletionRange == nil)
		#expect(controller.composer.string == "/sta")
	}

	@Test func externalDraftReplacementAndLateSelectionCannotExecuteOldCommand()
	{
		let controller = makeController(text: "/cop")
		let selected = SlashCommandRegistry.descriptor(for: .copy)
		var commands: [SlashCommandInvocation] = []
		controller.onSlashCommand =
		{
			commands.append($0)
		}
		controller.composer.string = "User edit 🧭"
		controller.chooseSlashCommand(
			selected,
			execute: true
		)
		#expect(commands.isEmpty)
		#expect(controller.composer.string == "User edit 🧭")
	}

	@Test func localCommandStaysSubmittableWhenNormalSendIsUnavailableAndPlanModeIsVisible()
	{
		let controller = makeController(text: "/status")
		#expect(controller.sendButton.isEnabled)
		var active = snapshot(draft: "/status")
		active.planMode = true
		active.slashCommandUnavailableReasons = [.compact: "Wait for the current turn to finish."]
		controller.render(active)
		#expect(!controller.planModeLabel.isHidden)
		#expect(controller.slashCommandController
			.unavailableReason?(.compact) == "Wait for the current turn to finish.")
		active.planMode = false
		active.planModeStatus = "Plan mode unknown: run /plan to reapply or reset."
		controller.render(active)
		#expect(!controller.planModeLabel.isHidden)
		#expect(controller.planModeLabel.stringValue == active.planModeStatus)
		controller.render(snapshot(draft: "Normal message"))
		#expect(!controller.sendButton.isEnabled)
	}

	@Test func selectionChangedDuringDraftPublicationCannotExecuteInReplacementOwner()
	{
		let controller = makeController(text: "/sta")
		var executions: [SlashCommandInvocation] = []
		controller.onSlashCommand =
		{
			executions.append($0)
		}
		controller.onDraftChange =
		{
			_ in
			var replacement = snapshot(draft: "Replacement draft")
			replacement.composerDraftLifetime = 1
			controller.render(replacement)
		}
		controller.chooseSlashCommand(
			SlashCommandRegistry.descriptor(for: .status),
			execute: true
		)
		#expect(executions.isEmpty)
		#expect(controller.composer.string == "Replacement draft")
	}

	@Test func skillsFilterByDisplayNameSkipHeadingAndAttachWithoutSending() throws
	{
		let controller = makeController(text: "/")
		let skill = try #require(AvailableSkill(json: [
			"name": "dashboard",
			"description": "Create a dashboard",
			"path": "/skills/dashboard",
			"scope": "user",
			"enabled": true,
			"interface": ["displayName": "Analytics Dashboard"],
		]))
		var next = snapshot(draft: "/")
		next.skillCatalog = SkillCatalog(
			skills: [skill],
			errors: []
		)
		controller.render(next)
		for _ in controller.slashCommandController.commands
		{
			controller.slashCommandController.moveSelection(by: 1)
		}
		#expect(controller.slashCommandController.selectedSkill == skill)
		controller.slashCommandController.moveSelection(by: -1)
		#expect(controller.slashCommandController.selectedCommand?.id == .copy)
		controller.composer.string = "/ANAL keep this prompt"
		controller.composer.setSelectedRange(NSRange(
			location: 5,
			length: 0
		))
		controller.updateComposerCompletion()
		#expect(controller.slashCommandController.commands.isEmpty)
		#expect(controller.slashCommandController.selectedSkill == skill)
		var selected: AvailableSkill?
		var sends = 0
		controller.onSelectSkill =
		{
			selected = $0
		}
		controller.onSend =
		{
			sends += 1
		}
		#expect(controller.handleSlashCommandKey(#selector(NSResponder.insertNewline(_:))))
		#expect(selected == skill)
		#expect(controller.composer.string == " keep this prompt")
		#expect(sends == 0)
		#expect(controller.slashCompletionRange == nil)
	}

	@Test func removedSkillAndReplacedDraftCannotAttachStaleSelection() throws
	{
		let controller = makeController(text: "/dashboard")
		let skill = try #require(AvailableSkill(json: [
			"name": "dashboard",
			"description": "Create a dashboard",
			"path": "/skills/dashboard",
			"scope": "user",
			"enabled": true,
		]))
		var next = snapshot(draft: "/dashboard")
		next.skillCatalog = SkillCatalog(
			skills: [skill],
			errors: []
		)
		controller.render(next)
		controller.updateComposerCompletion()
		var selections = 0
		controller.onSelectSkill =
		{
			_ in selections += 1
		}
		next.skillCatalog = nil
		controller.render(next)
		controller.chooseSlashSkill(skill)
		#expect(selections == 0)
		#expect(controller.composer.string == "/dashboard")
		next.skillCatalog = SkillCatalog(
			skills: [skill],
			errors: []
		)
		controller.render(next)
		controller.updateComposerCompletion()
		controller.onDraftChange =
		{
			_ in
			var replacement = snapshot(draft: "Replacement")
			replacement.composerDraftLifetime = 2
			controller.render(replacement)
		}
		controller.chooseSlashSkill(skill)
		#expect(selections == 0)
		#expect(controller.composer.string == "Replacement")
	}

	private func makeController(text: String) -> ConversationViewController
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		controller.render(snapshot(draft: text))
		controller.composer.setSelectedRange(NSRange(
			location: (text as NSString).length,
			length: 0
		))
		controller.updateComposerCompletion()
		return controller
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
