import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ModelEffortPopoverViewTests
{
	@Test func presentedMenuActionsEmitModelIDsAndBackendDefaultDirectly() throws
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

		let menu = picker.makeModelMenu()
		#expect(menu.items.map(\.title) == ["Default model", "First model", "Second model"])
		#expect(menu.items.map(\.state) == [.off, .off, .on])
		let first = menu.items[1]
		#expect(NSApp.sendAction(
			try #require(first.action),
			to: first.target,
			from: first
		))
		let backendDefault = menu.items[0]
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
		#expect(picker.makeModelMenu().items.map(\.state) == [.on, .off, .off])
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
		let menu = picker.makeModelMenu()
		#expect(
			menu.items.map(\.title) == [
				"Default model",
				"First model",
				"Second model",
				"Unavailable: missing",
			]
		)
		#expect(menu.items.map(\.state) == [.off, .off, .off, .on])
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
		let replacement = menu.items[2]
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
		#expect(picker.makeModelMenu().items.count == 3)
		#expect(label(
			in: picker.view,
			accessibilityLabel: "Selected reasoning effort"
		) == "Light")
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
