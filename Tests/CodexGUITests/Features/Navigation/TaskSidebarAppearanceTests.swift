import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct TaskSidebarAppearanceTests
{
	@Test func unreadColorUpdatesWithoutResettingHoverOrFocus() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let content = try #require(window.contentView)
		let cell = TaskSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 280,
			height: 32
		))
		content.addSubview(cell)
		cell.textField?.stringValue = "Appearance chat"
		cell.setUnread(true)
		let focus = NSTextView(frame: NSRect(
			x: 0,
			y: 50,
			width: 280,
			height: 80
		))
		content.addSubview(focus)
		#expect(window.makeFirstResponder(focus))
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
		cell.mouseEntered(with: event)
		let actions = try #require(cell.subviews.compactMap
		{
			$0 as? NSStackView
		}.first)
		let titleField = try #require(cell.textField)
		content.layoutSubtreeIfNeeded()
		let titleFrame = titleField.frame
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			content.layoutSubtreeIfNeeded()
			#expect(cell.appearance == nil)
			#expect(cell.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			try expectColor(
				cell.unreadDot.layer?.backgroundColor,
				.systemBlue,
				in: cell
			)
			#expect(!cell.unreadDot.isHidden)
			#expect(cell.unreadDot.alphaValue == 0)
			#expect(!actions.isHidden)
			#expect(actions.alphaValue == 1)
			#expect(cell.textField === titleField)
			#expect(titleField.frame == titleFrame)
			#expect(titleField.stringValue == "Appearance chat")
			#expect(window.firstResponder === focus)
		}
		cell.mouseExited(with: event)
		#expect(cell.unreadDot.alphaValue == 1)
	}

	@Test func existingHoverCardSurfaceDrawsInheritedColors() throws
	{
		let application = NSApplication.shared
		let originalAppearance = application.appearance
		defer
		{
			application.appearance = originalAppearance
		}
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let anchor = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 280,
			height: 32
		))
		window.contentView?.addSubview(anchor)
		let card = TaskHoverCard(
			title: "Chat",
			projectName: "Project",
			updatedAt: nil
		)
		card.show(beside: anchor)
		defer
		{
			card.dismiss()
		}
		let panel = try #require(card.panel)
		let surface = try #require(panel.contentView)
		let frame = panel.frame
		func verifyRetainedCard(_ appearance: NSAppearance.Name) throws
		{
			surface.layoutSubtreeIfNeeded()
			#expect(surface.appearance == nil)
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			#expect(surface.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
			surface.effectiveAppearance.performAsCurrentDrawingAppearance
			{
				surface.cacheDisplay(
					in: surface.bounds,
					to: bitmap
				)
			}
			let pixel = try #require(bitmap.colorAt(
				x: Int(5 * CGFloat(bitmap.pixelsWide) / surface.bounds.width),
				y: bitmap.pixelsHigh / 2
			))
			// colorAt labels raw components Generic RGB even for a display-profile bitmap.
			// Apply the bitmap profile before converting the sampled color.
			let taggedPixel = NSColor(
				colorSpace: bitmap.colorSpace,
				components: [
					pixel.redComponent,
					pixel.greenComponent,
					pixel.blueComponent,
					pixel.alphaComponent
				],
				count: 4
			)
			try expectColor(
				taggedPixel.cgColor,
				AppKitColorTokens.summaryCard,
				in: surface
			)
			#expect(card.panel === panel)
			#expect(panel.frame == frame)
			#expect(panel.parent === window)
			#expect(panel.ignoresMouseEvents)
		}

		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			try verifyRetainedCard(appearance)
		}

		window.appearance = nil
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			application.appearance = NSAppearance(named: appearance)
			try verifyRetainedCard(appearance)
		}
	}

	@Test func longHoverCardRemainsCompactAndInsideVisibleScreen() throws
	{
		_ = NSApplication.shared
		let screen = try #require(NSScreen.main)
		let window = NSWindow(
			contentRect: NSRect(
				x: screen.visibleFrame.maxX - 320,
				y: screen.visibleFrame.maxY - 180,
				width: 320,
				height: 180
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
		let anchor = NSView(frame: NSRect(
			x: 0,
			y: 140,
			width: 280,
			height: 32
		))
		window.contentView?.addSubview(anchor)
		let card = TaskHoverCard(
			title: String(
				repeating: "Long title\n",
				count: 300
			),
			projectName: String(
				repeating: "Long project ",
				count: 100
			),
			updatedAt: nil
		)
		card.show(beside: anchor)
		defer
		{
			card.dismiss()
		}
		let panel = try #require(card.panel)
		#expect(panel.frame.height <= 160)
		#expect(panel.frame.width <= 320)
		#expect(screen.visibleFrame.contains(panel.frame))
		#expect(panel.ignoresMouseEvents)
		#expect(!panel.isKeyWindow)
	}

	private func expectColor(
		_ actualCGColor: CGColor?,
		_ semantic: NSColor,
		in view: NSView,
		alpha: CGFloat = 1
	) throws
	{
		let actual = try #require(actualCGColor
			.flatMap
			{
				NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB)
			})
		var expected: NSColor?
		view.effectiveAppearance
			.performAsCurrentDrawingAppearance
			{
				expected = semantic.usingColorSpace(.deviceRGB)
			}
		let color = try #require(expected)
		#expect(abs(actual.redComponent - color.redComponent) < 0.01)
		#expect(abs(actual.greenComponent - color.greenComponent) < 0.01)
		#expect(abs(actual.blueComponent - color.blueComponent) < 0.01)
		#expect(abs(actual.alphaComponent - alpha) < 0.01)
	}
}
