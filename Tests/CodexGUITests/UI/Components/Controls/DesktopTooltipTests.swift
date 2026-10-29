import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopTooltipTests
{
	@Test func trackingOwnerReceivesNativePointerSelectorsForPlainButtonsAndPopups() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 300,
					height: 180
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			let button = DesktopTooltipButton(frame: NSRect(
				x: 20,
				y: 30,
				width: 100,
				height: 30
			))
			let popup = DesktopPopupButton(
				frame: NSRect(
					x: 150,
					y: 30,
					width: 100,
					height: 30
				),
				pullsDown: true
			)
			button.toolTip = "Select effort"
			popup.toolTip = "Add files and more"
			let imageZoom = ExpandedImageZoomButton(
				frame: NSRect(
					x: 260,
					y: 30,
					width: 80,
					height: 30
				),
				pullsDown: false
			)
			for control: NSControl in [button, popup, imageZoom]
			{
				try #require(window.contentView).addSubview(control)
				control.updateTrackingAreas()
				let owner = try #require(control.trackingAreas
					.compactMap
					{
						$0.owner as? DesktopControlTooltip
					}.first)
				let entered = #selector(NSResponder.mouseEntered(with:))
				let exited = #selector(NSResponder.mouseExited(with:))
				try #require(owner.responds(to: entered))
				try #require(owner.responds(to: exited))
				_ = owner.perform(
					entered,
					with: NSEvent()
				)
				await (try #require(owner.presentation.task)).value
				#expect(owner.presentation.panel?.parent === window)
				_ = owner.perform(
					exited,
					with: NSEvent()
				)
				#expect(owner.presentation.panel == nil)
			}
		}
	}

	@Test func shortcutCapsuleKeepsMeasuredSpacingAndShape() throws
	{
		let surface = DesktopTooltipView(
			text: "Search",
			style: .control,
			shortcut: "⌘K"
		)
		let size = surface.measuredSize(maximumWidth: 320)
		#expect(size.width == 106)
		#expect(size.height == 30)
		let badge = try #require(surface.shortcutBadge)
		let text = surface.label.alignmentRect(forFrame: surface.label.frame)
		#expect(abs(badge.frame.minX - text.maxX - 8) < 0.01)
		#expect(badge.frame.height == 18)
		#expect(badge.frame.maxX <= size.width - 5)
		let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
		surface.cacheDisplay(
			in: surface.bounds,
			to: bitmap
		)
		let scale = CGFloat(bitmap.pixelsWide) / surface.bounds.width
		let corner = try #require(bitmap.colorAt(
			x: Int(3.5 * scale),
			y: Int(5.5 * scale)
		))
		// This point is inside the measured superellipse and outside a circular capsule.
		#expect(corner.alphaComponent > 0.9)

	}

	@Test(arguments: [
		("Change permissions", DesktopTooltip.Style.control, CGFloat(320), nil as String?),
		("New Chat in codex-gui", .capsule, 320, nil),
		("Search conversation titles and previews", .control, 320, "⌘K"),
		("A longer tooltip that must wrap and keep its shortcut visible", .control, 160, "⌘K"),
		("A standard tooltip that must wrap completely", .standard, 160, nil),
		(
			"Submit this queued message with its captured context and attachments",
			.capsule,
			160,
			nil
		),
	])
	func tooltipFitsEveryTextLine(
		text: String,
		style: DesktopTooltip.Style,
		maximumWidth: CGFloat,
		shortcut: String?
	) throws
	{
		let surface = DesktopTooltipView(
			text: text,
			style: style,
			shortcut: shortcut
		)
		let wide = surface.measuredSize(maximumWidth: 1000)
		let size = surface.measuredSize(maximumWidth: maximumWidth)
		#expect(size.width <= maximumWidth)
		#expect(surface.bounds.contains(surface.label.alignmentRect(forFrame: surface.label.frame)))
		if maximumWidth == 160
		{
			#expect(size.height > wide.height)
		}
		if style == .control, shortcut != nil, maximumWidth == 160
		{
			let paragraph = try #require(surface.label.attributedStringValue.attribute(
				.paragraphStyle,
				at: 0,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(paragraph.alignment == .center)
		}
		for label in [surface.label] +
			(surface.shortcutBadge?.subviews.compactMap
			{
				$0 as? NSTextField
			} ?? [])
		{
			let cell = try #require(label.cell)
			let required = cell.cellSize(forBounds: NSRect(
				x: 0,
				y: 0,
				width: label.bounds.width,
				height: .greatestFiniteMagnitude
			))
			#expect(required.height <= label.bounds.height)
			#expect(required.width <= label.bounds.width)
		}
	}

	@Test func placementUsesRequestedSideAndFlipsBeforeClamping()
	{
		let screen = NSRect(
			x: 0,
			y: 0,
			width: 800,
			height: 600
		)
		let anchor = NSRect(
			x: 300,
			y: 200,
			width: 28,
			height: 28
		)
		let size = NSSize(
			width: 100,
			height: 30
		)
		#expect(DesktopTooltip.origin(
			for: size,
			anchor: anchor,
			screen: screen,
			placement: .above,
			gap: 2
		) == NSPoint(
			x: 264,
			y: 230
		))
		#expect(DesktopTooltip.origin(
			for: size,
			anchor: anchor,
			screen: screen,
			placement: .below,
			gap: 4
		) == NSPoint(
			x: 264,
			y: 166
		))
		#expect(DesktopTooltip.origin(
			for: size,
			anchor: anchor,
			screen: screen,
			placement: .right,
			gap: 2
		) == NSPoint(
			x: 330,
			y: 199
		))
		let upper = NSRect(
			x: 760,
			y: 560,
			width: 28,
			height: 28
		)
		let flipped = DesktopTooltip.origin(
			for: size,
			anchor: upper,
			screen: screen,
			placement: .above,
			gap: 2
		)
		#expect(flipped.y == 528)
		#expect(flipped.x + size.width <= screen.maxX - 8)
		let right = DesktopTooltip.origin(
			for: size,
			anchor: upper,
			screen: screen,
			placement: .right,
			gap: 2
		)
		#expect(right.x + size.width == upper.minX - 2)
	}

	@Test func focusAndHoverShareOnePanelAndRetirePendingPresentations() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 200
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			let first = DesktopTooltipButton(frame: NSRect(
				x: 30,
				y: 60,
				width: 60,
				height: 24
			))
			let second = DesktopTooltipButton(frame: NSRect(
				x: 120,
				y: 60,
				width: 60,
				height: 24
			))
			first.toolTip = "Search"
			second.toolTip = "Copy response"
			let host = try #require(window.contentView)
			host.addSubview(first)
			host.addSubview(second)
			window.layoutIfNeeded()
			#expect(window.makeFirstResponder(first))
			await (try #require(first.tooltipTask)).value
			let focusedPanel = try #require(first.controlTooltip.presentation.panel)
			#expect(window.firstResponder === first)
			#expect(focusedPanel.ignoresMouseEvents)
			second.mouseEntered(with: NSEvent())
			await (try #require(second.tooltipTask)).value
			#expect(focusedPanel.parent == nil)
			#expect(window.childWindows?.count == 1)
			#expect(window.firstResponder === first)
			let hoveredPanel = try #require(second.controlTooltip.presentation.panel)
			let escape = try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			))
			NSApp.sendEvent(escape)
			#expect(hoveredPanel.parent == nil)
			#expect(window.firstResponder === first)
			second.mouseEntered(with: NSEvent())
			await (try #require(second.tooltipTask)).value
			#expect(focusedPanel.parent == nil)
			#expect(window.childWindows?.count == 1)
			let disabledPanel = try #require(second.controlTooltip.presentation.panel)
			second.isEnabled = false
			#expect(!disabledPanel.isVisible && disabledPanel.parent == nil)
			second.isEnabled = true
			second.mouseExited(with: NSEvent())
			#expect(window.childWindows?.isEmpty != false)
			second.mouseEntered(with: NSEvent())
			let pending = try #require(second.tooltipTask)
			second.isEnabled = false
			await pending.value
			#expect(window.childWindows?.isEmpty != false)
			second.isEnabled = true
			second.mouseExited(with: NSEvent())
			second.mouseEntered(with: NSEvent())
			let detached = try #require(second.tooltipTask)
			second.removeFromSuperview()
			await detached.value
			#expect(second.tooltipTask == nil)
			#expect(window.childWindows?.isEmpty != false)
			_ = window.makeFirstResponder(nil)
		}
	}
}
