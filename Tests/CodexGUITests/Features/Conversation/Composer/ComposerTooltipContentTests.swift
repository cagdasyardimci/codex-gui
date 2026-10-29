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

	@Test func modelMenuHoverContentsRemainStableWhenFastModeChanges() throws
	{
		let picker = ModelEffortPopoverView()
		picker.loadViewIfNeeded()
		for fast in [false, true, false]
		{
			picker.render(
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				fastMode: fast
			)
			let buttons = descendants(picker.view).compactMap
			{
				$0 as? NSButton
			}
			let speed = try #require(buttons
				.first
				{
					$0.accessibilityLabel() == (fast ? "Disable fast mode" : "Enable fast mode")
				})
			#expect(speed.toolTip == "1.5x speed\nMore usage")
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
