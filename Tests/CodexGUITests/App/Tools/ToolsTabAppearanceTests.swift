import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ToolsTabAppearanceTests
{

	@Test func retainedTabSurfacesPaintSelectionAndHoverInBothAppearances() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 260,
				height: 80
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
		let selected = ToolsTabSurface(isSelected: true)
		let hovered = ToolsTabSurface(isSelected: false)
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		for tab in [selected, hovered]
		{
			tab.frame = NSRect(
				x: 0,
				y: 0,
				width: 238,
				height: 32
			)
			window.contentView?.addSubview(tab)
		}
		hovered.mouseEntered(with: event)
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: name)
			window.layoutIfNeeded()
			let dark = name == .darkAqua
			for (tab, expected) in [(selected, dark ? 53 : 255), (hovered, dark ? 53 : 234)]
			{
				let bitmap = try paint(
					tab,
					dark: dark
				)
				let center = try #require(bitmap.colorAt(
					x: 119,
					y: 16
				)?.usingColorSpace(.sRGB))
				#expect(abs(center.redComponent * 255 - CGFloat(expected)) <= 1)
				let corner = try #require(bitmap.colorAt(
					x: 0,
					y: 0
				)?.usingColorSpace(.sRGB))
				#expect(abs(corner.redComponent * 255 - CGFloat(dark ? 36 : 246)) <= 1)
				#expect(tab.bounds.size == NSSize(
					width: 238,
					height: 32
				))
			}
			hovered.mouseExited(with: event)
			let rest = try paint(
				hovered,
				dark: dark
			)
			let color = try #require(rest.colorAt(
				x: 119,
				y: 16
			)?.usingColorSpace(.sRGB))
			#expect(abs(color.redComponent * 255 - CGFloat(dark ? 36 : 246)) <= 1)
			hovered.mouseEntered(with: event)
			let shadow = try #require(selected.layer?.sublayers?.first)
			#expect(shadow.shadowRadius == 1)
			#expect(shadow.shadowPath?.boundingBox.width == 236)
		}
	}

	@Test func selectedTabPaintsSuperellipseCornersAndBorderOverItsBacking() throws
	{
		let tab = ToolsTabSurface(isSelected: true)
		tab.frame = NSRect(
			x: 0,
			y: 0,
			width: 238,
			height: 32
		)
		for name: NSAppearance.Name in [.aqua, .darkAqua]
		{
			tab.appearance = NSAppearance(named: name)
			let dark = name == .darkAqua
			let bitmap = try paint(
				tab,
				dark: dark,
				scale: 2
			)
			let border = try #require(bitmap.colorAt(
				x: 238,
				y: 0
			)?.usingColorSpace(.sRGB))
			#expect(abs(border.redComponent * 255 - CGFloat(dark ? 69 : 237)) <= 1)
			// At (2.75, 2.75), the reference superellipse is painted; radius-10 circular
			// corners leave this pixel outside the surface. Bounds and radius stay fixed.
			let corner = try #require(bitmap.colorAt(
				x: 5,
				y: 5
			)?.usingColorSpace(.sRGB))
			#expect(dark ? corner.redComponent * 255 > 50 : corner.redComponent * 255 > 250)
		}
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func paintedRedRange(
		_ bitmap: NSBitmapImageRep,
		in rect: NSRect
	) -> ClosedRange<Int>
	{
		var values: [Int] = []
		for y in Int(rect.minY * 2) ..< Int(rect.maxY * 2)
		{
			for x in Int(rect.minX * 2) ..< Int(rect.maxX * 2)
			{
				if let color = bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.sRGB)
				{
					values.append(Int((color.redComponent * 255).rounded()))
				}
			}
		}
		return (values.min() ?? 0) ... (values.max() ?? 0)
	}

	private func paint(
		_ tab: NSView,
		dark: Bool,
		tools: Bool = false,
		scale: CGFloat = 1
	) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(tab.bounds.width * scale),
			pixelsHigh: Int(tab.bounds.height * scale),
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
			x: scale,
			y: scale
		)
		tab.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			NSColor(
				srgbRed: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				green: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				blue: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				alpha: 1
			).setFill()
			tab.bounds.fill()
			tab.draw(tab.bounds)
		}
		return bitmap
	}
}
