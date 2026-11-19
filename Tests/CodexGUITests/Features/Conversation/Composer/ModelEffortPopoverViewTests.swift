import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ModelEffortPopoverViewTests
{

	@Test func unavailableSavedModelRemainsVisibleAndCanBeReplaced() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		var selections: [String?] = []
		#expect(picker.preferredContentSize.height == 104)
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
		#expect(picker.preferredContentSize.height == 104)
		picker.showModelList()
		let menu = picker.modelList
		#expect(
			menu.rows.map(\.title) == [
				"Default",
				"First model",
				"Second model",
				"missing",
			]
		)
		#expect(menu.rows.map(\.state) == [.off, .off, .off, .on])
		#expect(
			button(
				in: picker.view,
				accessibilityLabel: "Choose Codex model"
			)?.title
				== "missing"
		)
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "Ultra")
		#expect(button(
			in: picker.view,
			accessibilityLabel: "Choose speed"
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
		#expect(picker.preferredContentSize.height == 104)
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "Light")
	}

	@Test func speedMenuShowsAdvertisedTiersAndSelectsUltrafast() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 200,
					y: 300,
					width: 400,
					height: 220
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let picker = ModelEffortPopoverView()
			let anchor = NSButton(frame: NSRect(
				x: 40,
				y: 95,
				width: 40,
				height: 30
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let host = DesktopPopoverHost(
				presentation: .composer(DesktopPopoverHost.ComposerPlacement()),
				content: picker.view,
				controller: picker
			)
			host.show(from: anchor)
			defer
			{
				picker.setPresented(false)
				host.close()
				window.close()
			}
			let sol = try #require(ModelOption(json: [
				"model": "sol",
				"isDefault": true,
				"serviceTiers": [
					["id": "priority", "name": "Fast", "description": "2x speed"],
					["id": "ultrafast",
						"name": "Ultrafast",
						"description": "The fastest responses for latency-sensitive work."],
				],
			]))
			let astra = try #require(ModelOption(json: [
				"model": "astra",
				"serviceTiers": [["id": "priority", "name": "Fast", "description": "2x speed"]],
			]))
			var selections: [String] = []
			picker.onSelectSpeed =
			{
				selections.append($0)
			}
			picker.render(
				models: [sol, astra],
				selectedModelID: nil,
				selectedEffort: nil,
				fastMode: false,
				serviceTier: "priority"
			)
			let speed = try #require(button(
				in: picker.view,
				accessibilityLabel: "Choose speed"
			))
			try #require(speed.dispatchConfiguredAction())
			let menu = try #require(host.panel.childWindows?.first)
			let content = try #require(menu.contentView)
			let fast = try #require(button(
				in: content,
				accessibilityLabel: "Fast"
			) as? DesktopMenuRow)
			let ultra = try #require(button(
				in: content,
				accessibilityLabel: "Ultrafast"
			) as? DesktopMenuRow)
			#expect(fast.checked)
			#expect(!ultra.checked)
			#expect(ultra.rowHeight > fast.rowHeight)
			try #require(ultra.dispatchConfiguredAction())
			#expect(selections == ["ultrafast"])
			#expect(host.panel.childWindows?.contains(menu) != true)

			picker.render(
				models: [sol, astra],
				selectedModelID: "astra",
				selectedEffort: nil,
				fastMode: false,
				serviceTier: "default"
			)
			try #require(speed.dispatchConfiguredAction())
			let astraMenu = try #require(host.panel.childWindows?.first?.contentView)
			#expect(button(
				in: astraMenu,
				accessibilityLabel: "Ultrafast"
			) == nil)
			#expect((button(
				in: astraMenu,
				accessibilityLabel: "Standard"
			) as? DesktopMenuRow)?
				.checked == true)
		}
	}

	@Test func modelHoverMovesBetweenRowsWithoutChangingSelection() throws
	{
		_ = NSApplication.shared
		let list = ModelPickerListView()
		list.render(
			choices: [
				ModelPickerChoice(
					id: nil,
					title: "Default"
				),
				ModelPickerChoice(
					id: "first",
					title: "First"
				)
			],
			selectedID: "first"
		)
		let event = try #require(NSEvent.mouseEvent(
			with: .mouseMoved,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		))
		try #require(list.rows.count == 2)
		list.rows[0].mouseEntered(with: event)
		#expect(list.rows[0].isHovered)
		list.rows[1].mouseEntered(with: event)
		#expect(!list.rows[0].isHovered && list.rows[1].isHovered)
		list.rows[1].mouseExited(with: event)
		#expect(list.rows.allSatisfy
		{
			!$0.isHovered
		})
		#expect(list.rows.map(\.state) == [.off, .on])
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
