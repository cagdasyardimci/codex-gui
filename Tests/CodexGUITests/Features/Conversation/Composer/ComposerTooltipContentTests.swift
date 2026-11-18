import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerTooltipContentTests
{
	@Test func composerTransitionsPreserveActionContentsAndSubmissionAccessibility()
	{
		_ = NSApplication.shared
		var model = ComposerQueueTestFixture.model(messages: [])
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		for (draft, running) in [
			("", false),
			("An unsent message", false),
			("An unsent message", true),
			("An unsent message", false),
			("", false)
		]
		{
			model.composer.drafts[.thread("chat")] = ComposerDraft(text: draft)
			model.execution = running
				? ExecutionModel(
					activeThreadID: "chat",
					activeTurnID: "turn",
					state: .running
				)
				: ExecutionModel(state: .ready)
			let snapshot = WorkspaceSelectors.snapshot(
				model: model,
				now: Date()
			)
			#expect(snapshot.canQueue == running)
			controller.render(snapshot)
			#expect(controller.addContextButton.toolTip == "Add files and more")
			#expect(controller.addContextButton.controlTooltip.presentation.shortcut == "@")
			#expect(controller.modelEffortButton.toolTip == "Select effort")
			#expect(controller.modelEffortButton.tooltipShortcut == "⌃⇧M")
			#expect(controller.sendButton.toolTip == nil)
			#expect(controller.stopButton.toolTip == nil)
			#expect(controller.resumeButton.toolTip == nil)
			#expect(controller.sendButton
				.accessibilityLabel() == (running ? "Queue message" : "Send message"))
			#expect(controller.composer.draftText == draft)
			#expect(controller.sendButton.keyEquivalent == "\r")
		}
	}

	@Test func speedControlKeepsItsActionLabelAcrossTierChanges() throws
	{
		let picker = ModelEffortPopoverView()
		picker.loadViewIfNeeded()
		let model = try #require(ModelOption(json: [
			"model": "sol",
			"isDefault": true,
			"serviceTiers": [["id": "ultrafast", "name": "Ultrafast", "description": "Fastest"]],
		]))
		for (tier, name) in [("default", "Standard"), ("ultrafast", "Ultrafast")]
		{
			picker.render(
				models: [model],
				selectedModelID: nil,
				selectedEffort: nil,
				fastMode: false,
				serviceTier: tier
			)
			let buttons = descendants(picker.view).compactMap
			{
				$0 as? NSButton
			}
			let speed = try #require(buttons
				.first
				{
					$0.accessibilityLabel() == "Choose speed"
				})
			#expect(speed.accessibilityValue() as? String == name)
			let reset = try #require(buttons.first
			{
				$0.title == "Reset"
			})
			#expect(reset.toolTip == "Reset to default")
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews + view.subviews.flatMap
		{
			descendants($0)
		}
	}

}
