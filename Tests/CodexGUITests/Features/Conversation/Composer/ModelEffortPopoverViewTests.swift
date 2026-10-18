import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ModelEffortPopoverViewTests
{
	// ComposerPopoverPanel.show makes its panel key and installs application event monitors.
	@Test func shadowPaddingKeepsPopoverContentAnchoredWithoutNativeShadow(
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			_ = NSApplication.shared
			let visible = try #require(NSScreen.main).visibleFrame
			let window = NSWindow(
				contentRect: NSRect(
					x: visible.minX + 100,
					y: visible.minY + 100,
					width: 600,
					height: 420
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let anchor = NSButton(frame: NSRect(
				x: 200,
				y: 100,
				width: 220,
				height: 28
			))
			try #require(window.contentView).addSubview(anchor)
			let picker = ModelEffortPopoverView()
			let popover = ComposerPopoverPanel(
				contentViewController: picker,
				shadowOutset: LayoutTokens.ModelPopover.shadowOutset
			)
			popover.anchorSpacing = LayoutTokens.ModelPopover.anchorSpacing
			defer
			{
				popover.close()
				window.close()
			}
			popover.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			let panel = try #require(picker.view.window)
			panel.layoutIfNeeded()
			picker.view.layoutSubtreeIfNeeded()
			let contentFrame = panel.convertToScreen(picker.view.convert(
				picker.view.bounds,
				to: nil
			))
			let anchorFrame = window.convertToScreen(anchor.convert(
				anchor.bounds,
				to: nil
			))
			#expect(contentFrame.size == NSSize(
				width: 254,
				height: 96
			))
			#expect(abs(contentFrame.midX - anchorFrame.midX) < 1)
			#expect(contentFrame.minY - anchorFrame.maxY == 9)
			#expect(!panel.hasShadow)
			#expect(panel.frame.width - contentFrame.width == 48)
			#expect(panel.frame.height - contentFrame.height == 48)
			let backdrop = try #require(picker.view.subviews.compactMap
			{
				$0 as? NSVisualEffectView
			}.first)
			#expect(backdrop.blendingMode == .behindWindow)
			#expect(backdrop.layer?.masksToBounds == true)
			#expect(backdrop.layer?.cornerRadius == 20)
		}
	}

	@Test func referenceGeometryKeepsBackendTicksAndEffortActions() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		picker.render(
			models: try modelOptions(),
			selectedModelID: "first",
			selectedEffort: "high",
			fastMode: false
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 254,
				height: 96
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = picker
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		picker.view.layoutSubtreeIfNeeded()
		let effort = try #require(picker.view.subviews.compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.accessibilityLabel() == "Selected reasoning effort"
		})
		let model = try #require(button(
			in: picker.view,
			accessibilityLabel: "Choose Codex model"
		))
		let slider = try #require(picker.view.subviews.compactMap
		{
			$0 as? EffortSlider
		}.first)
		let cell = try #require(slider.cell as? EffortSliderCell)
		#expect(picker.view.bounds.maxY - effort.frame.maxY == 10)
		#expect(effort.frame.height == 20)
		#expect(picker.view.bounds.maxY - model.frame.maxY == 30)
		#expect(model.frame.height == 16)
		#expect(picker.view.bounds.maxY - slider.frame.maxY == 58)
		#expect(slider.frame.width == 230)
		#expect(slider.frame.minX == 12)
		#expect(cell.barRect(flipped: slider.isFlipped).height == 24)
		#expect(cell.barRect(flipped: slider.isFlipped).width == 230)
		#expect(slider.numberOfTickMarks == 2)
		#expect(cell.knobRect(flipped: slider.isFlipped).maxX == slider.bounds.maxX)
		var selected: String?
		picker.onSelectEffort =
		{
			selected = $0
		}
		slider.doubleValue = 0
		#expect(cell.rectOfTickMark(at: 0).width == 3)
		#expect(cell.rectOfTickMark(at: 1).width == 4)
		#expect(NSApp.sendAction(
			try #require(slider.action),
			to: slider.target,
			from: slider
		))
		#expect(selected == "low")
		picker.render(
			models: try modelOptions(),
			selectedModelID: "second",
			selectedEffort: nil,
			fastMode: false
		)
		#expect(slider.numberOfTickMarks == 1)
		#expect(slider.doubleValue == slider.tickMarkValue(at: 0))
	}

	@Test func presentedListActionsEmitModelIDsAndBackendDefaultDirectly() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		let models = try modelOptions()
		var selections: [String?] = []
		picker.onSelectModel =
		{
			selections.append($0)
		}
		picker.render(
			models: models,
			selectedModelID: "second",
			selectedEffort: nil,
			fastMode: false
		)

		picker.showModelList()
		let menu = picker.modelList
		#expect(menu.rows.map(\.title) == ["Default", "First model", "Second model"])
		#expect(menu.rows.map(\.state) == [.off, .off, .on])
		let first = menu.rows[1]
		#expect(NSApp.sendAction(
			try #require(first.action),
			to: first.target,
			from: first
		))
		picker.showModelList()
		let backendDefault = picker.modelList.rows[0]
		#expect(
			NSApp.sendAction(
				try #require(backendDefault.action),
				to: backendDefault.target,
				from: backendDefault
			)
		)
		#expect(selections.count == 2)
		#expect(selections[0] == "first")
		#expect(selections[1] == nil)

		picker.render(
			models: models,
			selectedModelID: nil,
			selectedEffort: nil,
			fastMode: false
		)
		picker.showModelList()
		#expect(picker.modelList.rows.map(\.state) == [.on, .off, .off])
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "High")
		#expect(
			button(
				in: picker.view,
				accessibilityLabel: "Choose Codex model"
			)?
				.title == "Default model"
		)
	}

	@Test func unavailableSavedModelRemainsVisibleAndCanBeReplaced() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		var selections: [String?] = []
		#expect(picker.preferredContentSize.height == 96)
		picker.onSelectModel =
		{
			selections.append($0)
		}
		let models = try modelOptions()
		picker.render(
			models: models,
			selectedModelID: "missing",
			selectedEffort: "ultra",
			fastMode: true
		)
		#expect(picker.preferredContentSize.height == 132)
		picker.showModelList()
		let menu = picker.modelList
		#expect(
			menu.rows.map(\.title) == [
				"Default",
				"First model",
				"Second model",
				"Unavailable: missing",
			]
		)
		#expect(menu.rows.map(\.state) == [.off, .off, .off, .on])
		#expect(
			button(
				in: picker.view,
				accessibilityLabel: "Choose Codex model"
			)?.title
				== "Unavailable: missing"
		)
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "Ultra")
		#expect(button(
			in: picker.view,
			accessibilityLabel: "Disable fast mode"
		)?.state == .on)
		let replacement = menu.rows[2]
		#expect(
			NSApp.sendAction(
				try #require(replacement.action),
				to: replacement.target,
				from: replacement
			)
		)
		#expect(selections == ["second"])
		picker.render(
			models: models,
			selectedModelID: "second",
			selectedEffort: nil,
			fastMode: true
		)
		picker.showModelList()
		#expect(picker.modelList.rows.count == 3)
		picker.setPresented(false)
		#expect(picker.preferredContentSize.height == 96)
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "Light")
	}

	@Test func retainedRowsCannotSelectAgainstAReplacementModelPresentation() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		let models = try modelOptions()
		picker.render(
			models: models,
			selectedModelID: "first",
			selectedEffort: nil,
			fastMode: false
		)
		picker.showModelList()
		let retired = picker.modelList.rows[1]
		picker.render(
			models: Array(models.suffix(1)),
			selectedModelID: "second",
			selectedEffort: nil,
			fastMode: false
		)
		var selected: [String?] = []
		picker.onSelectModel =
		{
			selected.append($0)
		}
		try #require(retired.dispatchConfiguredAction())
		#expect(selected.isEmpty)
		#expect(picker.isShowingModelList)
		let current = try #require(picker.modelList.rows.last)
		try #require(current.dispatchConfiguredAction())
		#expect(selected == ["second"])
		#expect(!picker.isShowingModelList)
		try #require(current.dispatchConfiguredAction())
		#expect(selected == ["second"])
	}

	private func modelOptions() throws -> [ModelOption]
	{
		let jsonModels: [[String: Any]] = [
			[
				"model": "first",
				"displayName": "First model",
				"isDefault": true,
				"defaultReasoningEffort": "high",
				"supportedReasoningEfforts": [
					["reasoningEffort": "low"],
					["reasoningEffort": "high"]
				],
			],
			[
				"model": "second",
				"displayName": "Second model",
				"isDefault": false,
				"defaultReasoningEffort": "low",
				"supportedReasoningEfforts": [["reasoningEffort": "low"]],
			],
		]
		return try jsonModels.map
		{
			try #require(ModelOption(json: $0))
		}
	}

	private func button(
		in view: NSView,
		accessibilityLabel: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == accessibilityLabel
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				in: $0,
				accessibilityLabel: accessibilityLabel
			)
		}.first
	}

	private func label(
		in view: NSView,
		accessibilityLabel: String
	) -> String?
	{
		if let label = view as? NSTextField, label.accessibilityLabel() == accessibilityLabel
		{
			return label.stringValue
		}
		return view.subviews.lazy.compactMap
		{
			label(
				in: $0,
				accessibilityLabel: accessibilityLabel
			)
		}.first
	}
}
