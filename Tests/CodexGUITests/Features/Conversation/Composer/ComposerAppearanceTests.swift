import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct ComposerAppearanceTests
{
	@Test func shownPanelTracksInheritedAppearanceAndRebindingWithoutReplacingContent() throws
	{
		_ = NSApplication.shared
		let applicationAppearance = NSApp.appearance
		let parent = makeWindow()
		let secondParent = makeWindow()
		let anchor = NSView(frame: NSRect(
			x: 20,
			y: 20,
			width: 80,
			height: 30
		))
		try #require(parent.contentView).addSubview(anchor)
		let content = NSViewController()
		let text = NSTextView(frame: NSRect(
			x: 0,
			y: 0,
			width: 220,
			height: 70
		))
		text.string = "Preserved selection"
		content.view = text
		content.preferredContentSize = text.frame.size
		let popover = ComposerPopoverPanel(contentViewController: content)
		popover.preservesParentKeyboardFocus = true
		defer
		{
			popover.close()
			parent.close()
			secondParent.close()
			NSApp.appearance = applicationAppearance
		}
		NSApp.appearance = NSAppearance(named: .aqua)
		popover.show(
			relativeTo: anchor.bounds,
			of: anchor
		)
		let panel = try #require(parent.childWindows?.first)
		#expect(panel.isVisible)
		#expect(panel.makeFirstResponder(text))
		let selection = NSRange(
			location: 3,
			length: 5
		)
		text.setSelectedRange(selection)
		let frame = panel.frame
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			NSApp.appearance = NSAppearance(named: name)
			#expect(content.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(parent.childWindows?.first === panel)
			#expect(panel.firstResponder === text)
			#expect(text.selectedRange() == selection)
			#expect(panel.frame == frame)
			#expect(popover.isShown)
		}
		anchor.appearance = NSAppearance(named: .darkAqua)
		popover.reposition()
		#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
		anchor.appearance = nil
		#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
		popover.close()
		let dismissedAppearance = panel.effectiveAppearance.name
		NSApp.appearance = NSAppearance(named: .darkAqua)
		#expect(panel.effectiveAppearance.name == dismissedAppearance)
		anchor.removeFromSuperview()
		try #require(secondParent.contentView).addSubview(anchor)
		secondParent.appearance = NSAppearance(named: .aqua)
		popover.show(
			relativeTo: anchor.bounds,
			of: anchor
		)
		#expect(secondParent.childWindows?.first === panel)
		#expect(content.view === text)
		#expect(text.selectedRange() == selection)
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua]
		{
			secondParent.appearance = NSAppearance(named: name)
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(secondParent.childWindows?.first === panel)
		}
	}

	@Test func sendAppearanceTracksDisabledStateWithoutChangingComposerFocusOrDraft() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let window = makeWindow()
		window.contentViewController = controller
		defer
		{
			window.close()
		}
		controller.composer.string = "Draft remains selected"
		let selection = NSRange(
			location: 2,
			length: 6
		)
		controller.composer.setSelectedRange(selection)
		#expect(window.makeFirstResponder(controller.composer))
		for enabled in [false, true, false]
		{
			controller.composerSubmissionPresentation = ConversationPresentation(snapshot(
				canSend: enabled,
				draft: controller.composer.string
			)).composer
			controller.updateSendState()
			#expect(controller.sendButton.isEnabled == enabled)
			let light = try #require(NSAppearance(named: .aqua))
			let dark = try #require(NSAppearance(named: .darkAqua))
			var resolved: [CGColor] = []
			for appearance in [light, dark, light, dark]
			{
				window.appearance = appearance
				let color = enabled
					? NSColor(
						srgbRed: 58 / 255,
						green: 131 / 255,
						blue: 247 / 255,
						alpha: 1
					)
					: .tertiaryLabelColor
				var expected: CGColor?
				controller.sendButton.effectiveAppearance.performAsCurrentDrawingAppearance
				{
					expected = color.cgColor
				}
				let actual = try #require(controller.sendButton.layer?.backgroundColor)
				#expect(actual == expected)
				resolved.append(actual)
				#expect(window.firstResponder === controller.composer)
				#expect(controller.composer.selectedRange() == selection)
				#expect(controller.composer.string == "Draft remains selected")
			}
			#expect(enabled ? resolved[0] == resolved[1] : resolved[0] != resolved[1])
		}
		controller.composerSubmissionPresentation = nil
		controller.updateSendState()
		#expect(!controller.sendButton.isEnabled)
		var disabledBackground: CGColor?
		controller.sendButton.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			disabledBackground = NSColor.tertiaryLabelColor.cgColor
		}
		#expect(controller.sendButton.layer?.backgroundColor == disabledBackground)
	}

	@Test func shownApprovalPanelRetainsRowsAndFocusAcrossWindowAppearanceChanges() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = makeWindow()
		window.contentViewController = controller
		window.appearance = NSAppearance(named: .aqua)
		window.orderFront(nil)
		window.layoutIfNeeded()
		controller.showApprovalPolicy()
		let popover = try #require(controller.approvalPolicyPopover)
		defer
		{
			popover.close()
			window.close()
		}
		#expect(popover.isShown)
		let content = controller.approvalPolicyController.view
		let panel = try #require(content.window)
		let stack = try #require(descendants(content).compactMap
		{
			$0 as? NSStackView
		}.first)
		let rows = stack.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}
		#expect(rows.count == 3)
		let selectedRow = try #require(rows.first)
		#expect(panel.makeFirstResponder(selectedRow))
		let selectedValue = selectedRow.accessibilityValue() as? String
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			#expect(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(popover.isShown)
			#expect(controller.approvalPolicyController.view === content)
			#expect(panel.firstResponder === selectedRow)
			#expect(selectedRow.accessibilityValue() as? String == selectedValue)
		}
	}

	@Test func shownModelEffortPanelPreservesSliderSelectionAndFocusAcrossAppearanceChanges() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = makeWindow()
		window.contentViewController = controller
		let model = try #require(ModelOption(json: [
			"model": "appearance-model",
			"displayName": "Appearance model",
			"supportedReasoningEfforts": [
				["reasoningEffort": "low"],
				["reasoningEffort": "medium"],
				["reasoningEffort": "high"],
			],
		]))
		controller.modelEffortController.render(
			models: [model],
			selectedModelID: model.id,
			selectedEffort: "high",
			fastMode: false
		)
		controller.showModelAndEffort()
		let popover = try #require(controller.modelEffortPopover)
		defer
		{
			popover.close()
			window.close()
		}
		let content = controller.modelEffortController.view
		let panel = try #require(content.window)
		let slider = try #require(descendants(content).compactMap
		{
			$0 as? NSSlider
		}.first)
		#expect(slider.isEnabled)
		#expect(panel.makeFirstResponder(slider))
		let selection = slider.doubleValue
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			#expect(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(popover.isShown)
			#expect(controller.modelEffortController.view === content)
			#expect(panel.firstResponder === slider)
			#expect(slider.doubleValue == selection)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func makeWindow() -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 600,
				height: 420
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func snapshot(
		canSend: Bool,
		draft: String
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/appearance",
			threads: [],
			selectedThreadID: "appearance",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: draft,
			canSend: canSend,
			accountDescription: "Mock",
			backendDescription: "Mock",
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
