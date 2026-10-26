import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationActivityCollectionItemTests
{

	// Native event polling and transient panels share the application event/window state.
	@Test func terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus(
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
			let window = TranscriptPointerTestWindow(
				contentRect: NSRect(
					x: NSEvent.mouseLocation.x - 92,
					y: NSEvent.mouseLocation.y - 52,
					width: 200,
					height: 100
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let button = ConversationTerminalCopyButton()
			button.setCopyImage(DesktopIcons.image(.copy))
			#expect(button.clipsToBounds)
			button.frame = NSRect(
				x: 80,
				y: 40,
				width: 24,
				height: 24
			)
			button.toolTip = "Copy output"
			try #require(window.contentView).addSubview(button)
			defer
			{
				button.resetHover()
				window.orderOut(nil)
			}
			window.orderFront(nil)
			let originalResponder = window.firstResponder
			// The cursor is inside the parent, but initially outside the copy button.
			button.frame.origin = NSPoint(
				x: 10,
				y: 10
			)
			button.updateTrackingAreas()
			#expect(!button.isHovered)
			#expect(button.image == nil)
			button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
			#expect(!button.isHovered)
			#expect(!button.isTooltipVisible)
			button.frame.origin = NSPoint(
				x: 80,
				y: 40
			)
			button.updateTrackingAreas()
			button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
			#expect(button.isHovered)
			#expect(button.isGlyphVisible)
			#expect(!button.isTooltipVisible)
			// Wait for the actual delayed tooltip operation, not a scheduling margin.
			await (try #require(button.tooltipTask)).value
			#expect(button.isTooltipVisible)
			#expect(window.firstResponder === originalResponder)
			if ProcessInfo.processInfo.environment["CODEX_TERMINAL_CAPTURE"] == "1"
			{
				let tooltip = try #require(window.childWindows?.first?.contentView)
				tooltip.layoutSubtreeIfNeeded()
				let bitmap = try #require(tooltip
					.bitmapImageRepForCachingDisplay(in: tooltip.bounds))
				tooltip.cacheDisplay(
					in: tooltip.bounds,
					to: bitmap
				)
				let png = try #require(bitmap.representation(
					using: .png,
					properties: [:]
				))
				try png.write(to: URL(fileURLWithPath: "/tmp/codex-terminal-copy-tooltip.png"))
			}
			let hoveredPoint = window.pointerLocation
			window.pointerLocation = .zero
			button.mouseExited(with: try hoverEvent(type: .mouseExited))
			#expect(!button.isHovered)
			#expect(!button.isGlyphVisible)
			#expect(!button.isTooltipVisible)
			window.pointerLocation = hoveredPoint
			button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
			let canceledTooltip = try #require(button.tooltipTask)
			// Tracking updates across the await must also observe the exited pointer.
			window.pointerLocation = .zero
			button.resetHover()
			await canceledTooltip.value
			#expect(!button.isHovered)
			#expect(!button.isTooltipVisible)
			window.makeFirstResponder(button)
			#expect(button.isGlyphVisible)
			#expect(!button.isHovered)
		}
	}

	@Test func activityDisclosureKeepsItsSubjectThroughHoverExpansionAndReuse() throws
	{
		_ = NSApplication.shared
		let item = ConversationActivityCollectionItem()
		var oldToggles = 0
		var newToggles = 0
		let collapsed = ConversationActivityRow(
			id: "first",
			sourceEntryID: "first",
			groupID: "first-group",
			kind: .group,
			title: "Tool calls"
		)
		item.configure(
			collapsed,
			onToggle:
			{
				oldToggles += 1
			},
			onOpenFile:
			{
				_ in
			}
		)
		let disclosure = try #require(descendants(item.view).compactMap
		{
			$0 as? DesktopDisclosureButton
		}.first)
		let enter = try hoverEvent(type: .mouseEntered)
		let exit = try hoverEvent(type: .mouseExited)
		for event in [enter, exit]
		{
			if event.type == .mouseEntered
			{
				disclosure.mouseEntered(with: event)
			}
			else
			{
				disclosure.mouseExited(with: event)
			}
			#expect(disclosure.accessibilityLabel() == "Expand Tool calls")
			#expect(disclosure.accessibilityValue() as? String == "Collapsed")
		}
		var expanded = collapsed
		expanded.expanded = true
		item.configure(
			expanded,
			onToggle:
			{
				oldToggles += 1
			},
			onOpenFile:
			{
				_ in
			}
		)
		disclosure.mouseEntered(with: enter)
		disclosure.mouseExited(with: exit)
		#expect(disclosure.accessibilityLabel() == "Collapse Tool calls")
		#expect(disclosure.accessibilityValue() as? String == "Expanded")
		var reboundToggles = 0
		item.configure(
			expanded,
			onToggle:
			{
				reboundToggles += 1
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(disclosure.dispatchConfiguredAction())
		#expect(reboundToggles == 1 && oldToggles == 0)
		item.prepareForReuse()
		disclosure.mouseEntered(with: enter)
		#expect(disclosure.accessibilityLabel() == "Expand")
		let next = ConversationActivityRow(
			id: "next",
			sourceEntryID: "next",
			groupID: "next-group",
			kind: .group,
			title: "Next actions"
		)
		item.configure(
			next,
			onToggle:
			{
				newToggles += 1
			},
			onOpenFile:
			{
				_ in
			}
		)
		disclosure.mouseExited(with: exit)
		#expect(disclosure.accessibilityLabel() == "Expand Next actions")
		#expect(disclosure.dispatchConfiguredAction())
		#expect(newToggles == 1 && oldToggles == 0)
	}

	private func layout(
		_ item: ConversationActivityCollectionItem,
		row: ConversationActivityRow
	)
	{
		item.view.frame = NSRect(
			origin: .zero,
			size: ConversationActivityCollectionItem.itemSize(
				row: row,
				width: 400
			)
		)
		item.view.layoutSubtreeIfNeeded()
		item.viewDidLayout()
		item.view.layoutSubtreeIfNeeded()
	}

	private func hoverEvent(type: NSEvent.EventType) throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: type,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}

	private func commandRow(
		expanded: Bool,
		output: String = ""
	) -> ConversationActivityRow
	{
		ConversationActivityRow(
			id: "command",
			sourceEntryID: "command",
			groupID: "group",
			kind: .command,
			title: "Ran printf",
			command: ConversationCommand(
				command: "printf 'first\\nlast\\n'",
				cwd: "/tmp",
				output: output,
				status: "completed",
				exitCode: 0,
				durationMs: 100,
				actions: []
			),
			expanded: expanded
		)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}

@MainActor
private final class TerminalRenderHost: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.white.setFill()
		bounds.fill()
	}
}
