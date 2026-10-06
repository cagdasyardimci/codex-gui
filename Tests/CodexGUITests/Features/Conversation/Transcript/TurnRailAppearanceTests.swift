import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnRailAppearanceTests
{
	@Test func existingPreviewFollowsWindowAndRailAppearanceUntilDismissal() throws
	{
		_ = NSApplication.shared
		let rail = TurnNavigationRail(frame: NSRect(
			x: 0,
			y: 0,
			width: 40,
			height: 180
		))
		let summaries = [
			ConversationTurnSummary(
				turnID: "first",
				entryID: "first:request",
				title: "First request",
				reply: "First reply"
			),
			ConversationTurnSummary(
				turnID: "second",
				entryID: "second:request",
				title: "Second request",
				reply: "Second reply"
			),
		]
		var loads = 0
		var bookmarks = 0
		rail.isBookmarked =
		{
			$0.turnID == "first"
		}
		rail.onLoadTurnPreview =
		{
			_ in loads += 1
		}
		rail.onBookmark =
		{
			_ in bookmarks += 1
		}
		rail.render(summaries)
		rail.updateActiveTurn("second")
		let window = NSWindow(
			contentRect: NSRect(
				x: -10000,
				y: -10000,
				width: 400,
				height: 200
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = try #require(NSAppearance(named: .aqua))
		try #require(window.contentView).addSubview(rail)
		defer
		{
			rail.dismissPreview()
			rail.removeFromSuperview()
			window.orderOut(nil)
		}
		rail.layoutSubtreeIfNeeded()
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let marks = try #require(scroll.documentView).subviews
			.compactMap
			{
				$0 as? TurnNavigationMark
			}
		try #require(marks.count == 2)
		let hovered = marks[0]
		#expect(window.makeFirstResponder(hovered))
		hovered.mouseEntered(with: try hoverEvent(
			.mouseEntered,
			window: window
		))
		let panel = try #require(rail.previewPanel)
		let preview = try #require(panel.contentView as? TurnSummaryPreview)
		preview.layoutSubtreeIfNeeded()
		let bookmark = try #require(descendants(preview).compactMap
		{
			$0 as? NSButton
		}.first)
		let texts = descendants(preview).compactMap
		{
			$0 as? NSTextField
		}
		let textValues = texts.map(\.stringValue)
		let frame = panel.frame
		let markFrames = marks.map(\.frame)
		let bookmarkFrame = bookmark.frame
		let height = preview.cardHeight
		#expect(loads == 1 && bookmarks == 0)
		#expect(textValues.contains("First request") && textValues.contains("First reply"))

		func verify(_ name: NSAppearance.Name) throws
		{
			panel.displayIfNeeded()
			#expect(rail.previewPanel === panel)
			#expect(panel.parent === window)
			#expect(panel.contentView === preview)
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(preview.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(panel.frame == frame && marks.map(\.frame) == markFrames)
			#expect(bookmark.frame == bookmarkFrame && preview.cardHeight == height)
			#expect(window.firstResponder === hovered)
			#expect(hovered.isEmphasized && !marks[1].isEmphasized)
			#expect(rail.activeTurnID == "second" && rail.summaries == summaries)
			#expect(!preview.isLoading && preview.accessibilityLabel() == "Turn preview")
			#expect(bookmark.accessibilityLabel() == "Remove turn bookmark")
			#expect(texts.map(\.stringValue) == textValues)
			#expect(loads == 1 && bookmarks == 0)
			try expectPreviewFill(preview)
		}

		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			#expect(rail.appearance == nil)
			try verify(name)
		}
		window.appearance = try #require(NSAppearance(named: .aqua))
		for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua]
		{
			rail.appearance = try #require(NSAppearance(named: name))
			try verify(name)
		}
		rail.appearance = nil
		try verify(.aqua)
		#expect(bookmark.sendAction(
			try #require(bookmark.action),
			to: bookmark.target
		))
		#expect(bookmarks == 1)
		#expect(rail.previewPanel === panel)

		rail.dismissPreview()
		#expect(rail.previewPanel == nil)
		#expect(panel.parent == nil && !panel.isVisible)
		#expect(window.childWindows?.contains(panel) != true)
		window.appearance = try #require(NSAppearance(named: .darkAqua))
		rail.appearance = try #require(NSAppearance(named: .darkAqua))
		#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
		hovered.mouseEntered(with: try hoverEvent(
			.mouseEntered,
			window: window
		))
		let reopened = try #require(rail.previewPanel)
		#expect(reopened !== panel)
		#expect(reopened.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
		#expect(reopened.parent === window && window.firstResponder === hovered)
		#expect(loads == 2)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private func expectPreviewFill(_ preview: NSView) throws
	{
		let bitmap = try #require(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
		preview.cacheDisplay(
			in: preview.bounds,
			to: bitmap
		)
		let pixel = try #require(bitmap.colorAt(
			x: bitmap.pixelsWide / 2,
			y: Int(3 * CGFloat(bitmap.pixelsHigh) / preview.bounds.height)
		))
		let actual = try #require(NSColor(
			colorSpace: bitmap.colorSpace,
			components: [
				pixel.redComponent,
				pixel.greenComponent,
				pixel.blueComponent,
				pixel.alphaComponent
			],
			count: 4
		).usingColorSpace(.deviceRGB))
		var expected: NSColor?
		preview.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			expected = NSColor.controlBackgroundColor.usingColorSpace(.deviceRGB)
		}
		let color = try #require(expected)
		#expect(abs(actual.redComponent - color.redComponent) < 2 / 255)
		#expect(abs(actual.greenComponent - color.greenComponent) < 2 / 255)
		#expect(abs(actual.blueComponent - color.blueComponent) < 2 / 255)
	}

	private func hoverEvent(
		_ type: NSEvent.EventType,
		window: NSWindow
	) throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: type,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}
}
