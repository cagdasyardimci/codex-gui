import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct HoverScrollingTextFieldTests
{
	@Test func hoverDelayPreservesNativeTextPosition() throws
	{
		_ = NSApplication.shared
		let field = makeField()
		defer
		{
			field.setHovered(false)
		}
		let resting = try pixels(of: render(field))
		field.setHovered(true)
		#expect(field.scrollOffset == 0)
		let hovered = try pixels(of: render(field))
		#expect(hovered == resting)
		field.advanceScrolling(elapsed: 0.59)
		#expect(field.scrollOffset == 0)
		let delayed = try pixels(of: render(field))
		#expect(delayed == resting)
		field.setHovered(false)
		let reset = try pixels(of: render(field))
		#expect(reset == resting)
	}

	@Test func scrollingPreservesTheNativeBaselineAndResetsOnExit() throws
	{
		_ = NSApplication.shared
		let field = makeField()
		defer
		{
			field.setHovered(false)
		}
		let resting = try inkRows(in: render(field))
		field.setHovered(true)
		field.advanceScrolling(elapsed: 0.8)
		if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			#expect(field.scrollOffset > 0)
			let scrolled = try inkRows(in: render(field))
			#expect(scrolled == resting)
		}
		field.setHovered(false)
		#expect(field.scrollOffset == 0)
		let reset = try inkRows(in: render(field))
		#expect(reset == resting)
	}

	private func makeField() -> HoverScrollingTextField
	{
		let field = HoverScrollingTextField(labelWithString: String(
			repeating: "M",
			count: 40
		))
		field.frame = NSRect(
			x: 0,
			y: 0,
			width: 120,
			height: 20
		)
		field.font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		field.textColor = .black
		field.appearance = NSAppearance(named: .aqua)
		field.lineBreakMode = .byTruncatingTail
		field.maximumNumberOfLines = 1
		field.cell?.usesSingleLineMode = true
		field.cell?.isScrollable = false
		return field
	}

	private func render(_ field: NSTextField) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 240,
			pixelsHigh: 40,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		context.cgContext.scaleBy(
			x: 2,
			y: 2
		)
		field.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			NSColor.white.setFill()
			field.bounds.fill()
			field.draw(field.bounds)
		}
		return bitmap
	}

	private func pixels(of bitmap: NSBitmapImageRep) throws -> [UInt8]
	{
		let data = try #require(bitmap.bitmapData)
		return Array(UnsafeBufferPointer(
			start: data,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		))
	}

	private func inkRows(in bitmap: NSBitmapImageRep) throws -> Set<Int>
	{
		var rows: Set<Int> = []
		for y in 0 ..< bitmap.pixelsHigh
		{
			// Exclude the truncated tail; the repeating glyphs keep the same vertical ink.
			for x in 0 ..< 100
			{
				let color = try #require(bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.sRGB))
				if color.redComponent < 0.5
				{
					rows.insert(y)
				}
			}
		}
		#expect(!rows.isEmpty)
		return rows
	}
}
