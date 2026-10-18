import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.testTiming
) @MainActor
struct ModelPickerListTests
{
	// Shows a key composer panel and tests focus across its content replacement.
	@Test func modelListReplacesEffortPanelAndRestoresTriggerSummary() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let setup = TestTiming.begin("native.setup")
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = try makeWindow(controller)
			setup.end()
			defer
			{
				controller.modelEffortPopover?.close()
				window.close()
			}
			controller.latestModelEffortSummary = "Fixture model 2 High"
			controller.modelEffortController.render(
				models: try models(count: 7),
				selectedModelID: "model-2",
				selectedEffort: "high",
				fastMode: false
			)
			let presentation = TestTiming.begin("native.presentation")
			controller.showModelAndEffort()
			controller.view.layoutSubtreeIfNeeded()
			controller.modelEffortPopover?.reposition()
			let picker = controller.modelEffortController
			let panel = try #require(picker.view.window)
			panel.layoutIfNeeded()
			presentation.end()
			let initialBottom = panel.convertToScreen(picker.view.convert(
				picker.view.bounds,
				to: nil
			))
			.minY
			let anchorTop = window.convertToScreen(controller.modelEffortButton.convert(
				controller.modelEffortButton.bounds,
				to: nil
			)).maxY
			#expect(initialBottom - anchorTop == 9)
			#expect(controller.modelEffortButton.title == "Select effort")
			picker.showModelList()
			panel.layoutIfNeeded()
			picker.view.layoutSubtreeIfNeeded()
			#expect(picker.view.window === panel)
			#expect(picker.view.bounds.size == NSSize(
				width: 254,
				height: 279
			))
			#expect(panel.convertToScreen(picker.view.convert(
				picker.view.bounds,
				to: nil
			)).minY
				== initialBottom)
			#expect(controller.modelEffortButton.title == "Fixture model 2 High")
			#expect(picker.modelList.accessibilityRole() == .menu)
			let rows = picker.modelList.rows
			#expect(rows.count == 8)
			#expect(rows.map(\.state) == [.off, .off, .off, .on, .off, .off, .off, .off])
			#expect(rows[0].preferredHeight == 44.5703125)
			#expect(rows[1].preferredHeight == 28.5703125)
			#expect(abs(rows[0].frame.height - rows[0].preferredHeight) < 1 / panel
				.backingScaleFactor)
			#expect(abs(rows[1].frame.height - rows[1].preferredHeight) < 1 / panel
				.backingScaleFactor)
			#expect(rows.allSatisfy
			{
				abs($0.frame.width - 246) < 0.01
			})
			#expect(rows[0].accessibilityHelp() == "Recommended set of models")
			#expect(rows[3].accessibilityRole() == .menuItem)
			#expect(panel.firstResponder === rows[3])
			rows[3].keyDown(with: try key(
				125,
				window: panel
			))
			#expect(panel.firstResponder === rows[4])
			window.appearance = NSAppearance(named: .darkAqua)
			#expect(rows[4].effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
			#expect(panel.firstResponder === rows[4])
			picker.render(
				models: try models(count: 100),
				selectedModelID: "model-2",
				selectedEffort: "high",
				fastMode: false
			)
			panel.layoutIfNeeded()
			picker.view.layoutSubtreeIfNeeded()
			let limitedFrame = panel.convertToScreen(picker.view.convert(
				picker.view.bounds,
				to: nil
			))
			#expect(limitedFrame.minY == initialBottom)
			#expect(limitedFrame.height < picker.preferredContentSize.height)
			let screenTop = try #require(NSScreen.main).visibleFrame.maxY
			#expect(limitedFrame.maxY <= screenTop - 7)
			picker.setPresented(false)
			#expect(!picker.isShowingModelList)
			#expect(picker.preferredContentSize.height == 96)
		}
	}

	@Test func limitedViewportScrollsToKeyboardDestinationAndPreservesBackendID() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		picker.render(
			models: try models(count: 40),
			selectedModelID: "model-1",
			selectedEffort: "high",
			fastMode: false
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 254,
				height: 180
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
		picker.showModelList()
		window.layoutIfNeeded()
		picker.view.layoutSubtreeIfNeeded()
		picker.modelList.focusSelectedRow()
		let first = picker.modelList.rows[2]
		first.keyDown(with: try key(
			119,
			window: window
		))
		let last = try #require(picker.modelList.rows.last)
		#expect(window.firstResponder === last)
		#expect(last.visibleRect.height > 0)
		var selected: String?
		picker.onSelectModel =
		{
			selected = $0
		}
		last.keyDown(with: try key(
			36,
			window: window
		))
		#expect(selected == "model-39")
		#expect(!picker.isShowingModelList)
	}

	@Test func movingHoverInvalidatesOnlyThePreviouslyHoveredRowAndDestination() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let list = ModelPickerListView()
			list.render(
				choices: (0 ..< 20).map
				{
					ModelPickerChoice(
						id: "model-\($0)",
						title: "Model \($0)"
					)
				},
				selectedID: nil
			)

			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 300,
					height: list.preferredHeight
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			defer
			{
				window.close()
			}
			window.contentView = list
			window.orderFront(nil)
			window.layoutIfNeeded()
			list.layoutSubtreeIfNeeded()
			window.displayIfNeeded()
			try #require(list.rows[3].bounds.width > 0)
			try #require(list.rows[3].bounds.height > 0)
			try #require(!list.rows[3].visibleRect.isEmpty)

			let event = try #require(NSEvent.enterExitEvent(
				with: .mouseEntered,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				trackingNumber: 0,
				userData: nil
			))
			// Layer-backed buttons transfer display invalidation to their backing layers.
			for row in list.rows
			{
				row.displayIfNeeded()
				row.layer?.displayIfNeeded()
			}
			list.rows[3].mouseEntered(with: event)
			#expect(list.rows.indices.filter
			{
				list.rows[$0].needsDisplay || list.rows[$0].layer?.needsDisplay() == true
			} == [3])
			for row in list.rows
			{
				row.displayIfNeeded()
				row.layer?.displayIfNeeded()
			}
			list.rows[12].mouseEntered(with: event)
			#expect(list.rows.indices.filter
			{
				list.rows[$0].needsDisplay || list.rows[$0].layer?.needsDisplay() == true
			} == [3, 12])
			for row in list.rows
			{
				row.displayIfNeeded()
				row.layer?.displayIfNeeded()
			}
			list.rows[3].clearHover()
			#expect(list.rows.allSatisfy
			{
				!$0.needsDisplay && $0.layer?.needsDisplay() != true
			})
		}
	}

	private func makeWindow(_ controller: NSViewController) throws -> NSWindow
	{
		let visible = try #require(NSScreen.main).visibleFrame
		let window = NSWindow(
			contentRect: NSRect(
				x: visible.minX + 100,
				y: visible.minY + 100,
				width: 888,
				height: 600
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 888,
			height: 600
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		return window
	}

	private func models(count: Int) throws -> [ModelOption]
	{
		try (0 ..< count).map
		{
			index in
			try #require(ModelOption(json: [
				"model": "model-\(index)",
				"displayName": "Fixture model \(index)",
				"supportedReasoningEfforts": [["reasoningEffort": "high"]],
			]))
		}
	}

	private func key(
		_ code: UInt16,
		window: NSWindow
	) throws -> NSEvent
	{
		try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: code
		))
	}
}
